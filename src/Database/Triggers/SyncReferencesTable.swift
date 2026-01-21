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
		}, when: { _, block in
			block.string.isNot(nil)
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.title, forEachRow: { old, new in
			Values($updatePageTitleInReferences(old: old.title.unsafelyUnwrapped, new: new.title.unsafelyUnwrapped, forPageID: new.id))
		}, when: { _, block in
			block.title.isNot(nil) && Reference.where { $0.targetBlockId == block.id }.exists()
		})).execute(db)
	}
}

@DatabaseFunction
func syncReferencesFromText(new: String, forBlockID blockID: Paragraph.ID, hasExistingReferencesInDatabase: Bool) throws {
	Task {
		@Dependency(\.context) var context
		@Dependency(\.defaultDatabase) var database

		if context == .preview {
			// Seeding happens synchronously in preview mode, so we need to yield to let migrations complete
			// If we get `cannot find table pages` errors in previews, increase this delay (sigh)
			try await Task.sleep(for: .seconds(2))
		}

		await withErrorReporting {
			try await database.write { db in
				let references = try new.extractRefs().map { try $0.resolved(using: db) }
				guard !references.isEmpty else { return }

				if hasExistingReferencesInDatabase {
					try Reference.where { $0.sourceBlockId == blockID }.delete().execute(db)
				}

				try Reference.insert {
					for reference in references {
						Reference(id: UUID(), sourceBlockId: blockID, targetBlockId: reference.targetID, kind: reference.kind)
					}
				}.execute(db)
			}
		}
	}
}

@DatabaseFunction
func updatePageTitleInReferences(old: String, new: String, forPageID pageID: Page.ID) throws {
	Task {
		@Dependency(\.defaultDatabase) var database

		withErrorReporting {
			try database.write { db in
				let blocks = try Reference.where { $0.targetBlockId.eq(pageID) }.join(Paragraph.all) { $0.sourceBlockId == $1.id }.select { $1 }.fetchAll(db)

				for block in blocks {
					let references = block.string.extractRefs().filter { $0.kind.isPage && $0.target == old }

					if !references.isEmpty {
						try Paragraph.find(block.id).update {
							var string = block.string

							for reference in references {
								string = string.replacingOccurrences(of: old, with: new, range: reference.range)
							}

							$0.string = string
						}.execute(db)
					}
				}
			}
		}
	}
}
