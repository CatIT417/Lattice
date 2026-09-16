import Foundation
import SQLiteData

struct SyncReferencesTable: Trigger {
	static var uses: [any ScalarDatabaseFunction] {
		[Self().$syncReferencesFromText, Self().$mergeRenamedPage, Self().$updatePageTitleInReferences]
	}

	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Select(Self().$syncReferencesFromText(new: block.string.unsafelyUnwrapped, forBlockID: block.id))
		}, when: {
			$0.string.isNot(nil)
		}))
		.execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.string, forEachRow: { _, block in
			Select(Self().$syncReferencesFromText(new: block.string.unsafelyUnwrapped, forBlockID: block.id))
		}, when: { old, new in
			new.string.isNot(nil) && old.string.isNot(new.string)
		}))
		.execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.title, forEachRow: { old, new in
			Select(Self().$mergeRenamedPage(id: new.id, oldTitle: old.title.unsafelyUnwrapped))

			Block.where { $0.id.asOptional.in(Block.find(new.id).select(\.mergedInto)) }
				.update { $0.title = new.title }

			Select(Self().$updatePageTitleInReferences(old: old.title.unsafelyUnwrapped, new: new.title.unsafelyUnwrapped))
		}, when: { old, new in
			!SyncEngine.$isSynchronizing && old.title.isNot(nil) && new.title.isNot(nil) && old.title.isNot(new.title)
				&& old.deletedAt.is(nil) && old.mergedInto.is(nil) && new.deletedAt.is(nil) && new.mergedInto.is(nil)
		}))
		.execute(db)

		try Block.createTemporaryTrigger(after: .delete { block in
			Reference.where { $0.sourceBlockId.eq(block.id) }.delete()
		})
		.execute(db)
	}

	@DatabaseFunction
	func syncReferencesFromText(new: String, forBlockID blockID: Paragraph.ID) throws {
		@Dependency(\.defaultDatabase) var database
		try database.unsafeReentrantWrite { db in
			let parsed = new.extractRefs()
			let references = Set(parsed.compactMap { Reference(sourceBlockId: blockID, reference: $0) })

			try Reference.where { $0.sourceBlockId.eq(blockID) }.delete().execute(db)
			if !references.isEmpty {
				try Reference.insert { Array(references) }.execute(db)
			}

			if !SyncEngine.isSynchronizing {
				var created = Set<String>()
				for title in parsed.filter(\.kind.isPage).map(\.target) where created.insert(title).inserted {
					_ = try Page.findOrCreate(title: title, in: db)
				}
			}
		}
	}

	@DatabaseFunction
	func mergeRenamedPage(id: Page.ID, oldTitle: String) throws {
		@Dependency(\.defaultDatabase) var database
		try database.unsafeReentrantWrite { db in
			let duplicates = try Page.where { $0.canonicalTitle.eq(oldTitle) }.select(\.id).fetchAll(db)
			try MergeDuplicatePages.merge(id, with: duplicates, in: db)
		}
	}

	@DatabaseFunction
	func updatePageTitleInReferences(old: String, new: String) throws {
		@Dependency(\.defaultDatabase) var database

		try database.unsafeReentrantWrite { db in
			let blocks = try Reference
				.group(by: \.sourceBlockId)
				.where { $0.kind.in([Reference.Kind.pageLink, .tag]) && $0.targetKey.eq(old) }
				.join(Paragraph.all) { $0.sourceBlockId.eq($1.id) }
				.select { $1 }
				.fetchAll(db)

			for block in blocks {
				let original = block.string
				let references = original.extractRefs().filter {
					$0.kind.isPage && $0.target == old
				}
				guard !references.isEmpty else { continue }

				let mutable = NSMutableString(string: original)
				let ranges = references
					.map { ref in
						(ref: ref, range: NSRange(ref.range, in: original))
					}
					.sorted { $0.range.location > $1.range.location }

				for item in ranges {
					guard let replacement = item.ref.replacement(forRenamedPage: new, in: original) else { continue }
					mutable.replaceCharacters(in: item.range, with: replacement)
				}

				let updated = mutable as String
				guard updated != original else { continue }

				try Block.find(block.id)
					.update { $0.string = #bind(updated) }
					.execute(db)
			}
		}
	}
}
