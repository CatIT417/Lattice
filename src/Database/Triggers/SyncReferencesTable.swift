import Foundation
import SQLiteData

final class SyncReferencesTable: Trigger {
	static var uses: [any ScalarDatabaseFunction] {
		[$syncReferencesFromText, $updatePageTitleInReferences]
	}

	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Values($syncReferencesFromText(
				new: block.string.unsafelyUnwrapped,
				forBlockID: block.id,
				hasExistingReferencesInDatabase: Reference.where { $0.sourceBlockId == block.id }.exists()
			))
		}, when: { block in
			block.string.isNot(nil)
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.string, forEachRow: { _, block in
			Values($syncReferencesFromText(
				new: block.string.unsafelyUnwrapped,
				forBlockID: block.id,
				hasExistingReferencesInDatabase: Reference.where { $0.sourceBlockId == block.id }.exists()
			))
		}, when: { old, new in
			new.string.isNot(nil) && old.string != new.string
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.title, forEachRow: { old, new in
			Values($updatePageTitleInReferences(old: old.title.unsafelyUnwrapped, new: new.title.unsafelyUnwrapped, forPageID: new.id))
		}, when: { old, new in
			new.title.isNot(nil) && old.title != new.title && Reference.where { $0.targetBlockId == new.id }.exists()
		})).execute(db)
	}
}

@DatabaseFunction
func syncReferencesFromText(new: String, forBlockID blockID: Paragraph.ID, hasExistingReferencesInDatabase: Bool) throws {
	@Dependency(\.uuid) var uuid
	@Dependency(\.defaultDatabase) var database

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			let references = try new.extractRefs().map { try $0.resolved(using: db) }

			if hasExistingReferencesInDatabase {
				try Reference.where { $0.sourceBlockId == blockID }.delete().execute(db)
			}

			guard !references.isEmpty else { return }

			try Reference.insert {
				for reference in references {
					Reference(id: uuid(), sourceBlockId: blockID, targetBlockId: reference.targetID, kind: reference.kind)
				}
			}.execute(db)
		}
	}
}

@DatabaseFunction
func updatePageTitleInReferences(old: String, new: String, forPageID pageID: Page.ID) throws {
	@Dependency(\.defaultDatabase) var database

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			let blocks = try Reference
				.group(by: \.sourceBlockId)
				.where { $0.targetBlockId.eq(pageID) }
				.join(Paragraph.all) { $0.sourceBlockId == $1.id }
				.select { $1 }
				.fetchAll(db)

			for block in blocks {
				let original = block.string
				let references = original.extractRefs().filter { $0.kind.isPage && $0.target == old }
				guard !references.isEmpty else { continue }

				let mutable = NSMutableString(string: original)
				let ranges = references
					.map { ref in
						(ref: ref, range: NSRange(ref.range, in: original))
					}
					.sorted { $0.range.location > $1.range.location }

				for item in ranges {
					guard let replacement = item.ref.replacement(forRenamedPage: new) else { continue }
					mutable.replaceCharacters(in: item.range, with: replacement)
				}

				let updated = mutable as String
				guard updated != original else { continue }

				try Block.find(block.id).update {
					$0.string = updated
				}.execute(db)
			}
		}
	}
}
