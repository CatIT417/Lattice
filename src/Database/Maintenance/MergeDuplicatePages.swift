import Foundation
import SQLiteData

/// Merges pages that share a title into the oldest one.
///
/// Titles cannot carry a UNIQUE constraint (CloudKit sync forbids it), so two devices can each create the same page
/// before they sync. This must only run from app code, never from a trigger: a merge performed while the sync engine
/// is applying remote rows inherits its "synchronizing" state, and none of its writes would be uploaded.
///
/// The keeper is chosen by `(createdAt, id)`, both of which are replicated, so every device merges the same way.
enum MergeDuplicatePages {
	struct Merge: Equatable, Sendable {
		let loser: Page.ID
		let keeper: Page.ID
	}

	static var duplicateTitles: some PartialSelectStatement<String> {
		Page
			.group(by: \.title)
			.having { $0.id.count() > 1 }
			.select(\.title)
	}

	@discardableResult static func run() async throws -> [Merge] {
		@Dependency(\.defaultDatabase) var database

		return try await database.write { try MergeDuplicatePages.run(in: $0) }
	}

	@discardableResult static func run(in db: Database) throws -> [Merge] {
		assert(!SyncEngine.isSynchronizing, "MergeDuplicatePages must not run inside the sync engine's write")

		var merges = [Merge]()

		for title in try duplicateTitles.fetchAll(db) {
			var pages = try Page
				.where { $0.title.eq(title) }
				.order { ($0.createdAt.asc(), $0.id.asc()) }
				.fetchAll(db)
			guard pages.count > 1 else { continue }

			let keeper = pages.removeFirst()

			for loser in pages {
				try merge(loser, into: keeper, in: db)
				merges.append(Merge(loser: loser.id, keeper: keeper.id))
			}
		}

		return merges
	}

	private static func merge(_ loser: Page, into keeper: Page, in db: Database) throws {
		let affectedBlocks = try Paragraph.where { $0.pageId.eq(loser.id) || $0.parentId.eq(loser.id) }.fetchAll(db)

		for block in affectedBlocks {
			try Block.find(block.id)
				.update {
					$0.pageId = #bind(keeper.id)

					if block.parentId == loser.id {
						$0.parentId = #bind(keeper.id)
					}
				}
				.execute(db)
		}

		try Reference.where { $0.targetBlockId.eq(loser.id) }.update { $0.targetBlockId = keeper.id }.execute(db)

		try Page.find(loser.id).delete().execute(db)
	}
}
