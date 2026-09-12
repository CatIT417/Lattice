import Foundation
import SQLiteData

enum MergeDuplicatePages {
	struct Merge: Equatable, Sendable {
		let loser: Page.ID
		let keeper: Page.ID
	}

	static var duplicateTitles: some PartialSelectStatement<String> {
		Page.group(by: \.title).having { $0.id.count() > 1 }.select(\.title)
	}

	private static var duplicateDates: some PartialSelectStatement<DayOfYear> {
		Page.where { $0.dailyNoteDate.isNot(nil) }
			.group(by: \.dailyNoteDate).having { $0.id.count() > 1 }
			.select { $0.dailyNoteDate.unsafelyUnwrapped }
	}

	private static var redirectChildren: Where<Block> {
		Block.where {
			$0.parentId.unsafelyUnwrapped.in(
				Block.where { $0.mergedInto.isNot(nil) }
					.join(BlockHierarchy.all) { $0.id.eq($1.blockId) && $1.pageId.isNot(nil) }
					.select { blocks, _ in blocks.id }
			)
		}
	}

	@discardableResult static func merge(_ pageID: Page.ID, with duplicates: [Page.ID], in db: Database) throws -> Page.ID {
		let keeper = duplicates.reduce(pageID) { $0.uuidString < $1.uuidString ? $0 : $1 }
		let losers = (duplicates + [pageID]).filter { $0 != keeper }
		if !losers.isEmpty {
			try Block.where { $0.id.in(losers) }
				.update { $0.mergedInto = #bind(keeper) }
				.execute(db)
		}
		return keeper
	}

	static func hasPendingWork(in db: Database) throws -> Bool {
		return try Select<Bool, ValuesColumns<Bool>, ()>(duplicateTitles.exists() || duplicateDates.exists() || redirectChildren.exists()).fetchOne(db) ?? false
	}

	@discardableResult static func run() async throws -> [Merge] {
		@Dependency(\.defaultDatabase) var database
		return try await database.write { try run(in: $0) }
	}

	@discardableResult static func run(in db: Database) throws -> [Merge] {
		assert(!SyncEngine.isSynchronizing, "Run page merges after the sync transaction.")
		var merges: [Merge] = []
		let pages = try Page.where {
			$0.title.in(duplicateTitles) || $0.dailyNoteDate.unsafelyUnwrapped.in(duplicateDates)
		}.order(by: \.id).select { ($0.id, $0.title, $0.dailyNoteDate) }.fetchAll(db)
		var titles: [String: Page.ID] = [:]
		var dates: [DayOfYear: Page.ID] = [:]
		for (id, title, day) in pages {
			let duplicate = titles[title] ?? day.flatMap { dates[$0] }
			let keeper = try merge(id, with: duplicate.map { [$0] } ?? [], in: db)
			if keeper != id {
				merges.append(Merge(loser: id, keeper: keeper))
			}
			titles[title] = keeper
			if let day { dates[day] = keeper }
		}

		let children = try redirectChildren.order { ($0.parentId, $0.order, $0.id) }
			.join(BlockHierarchy.all) { $0.parentId.eq($1.blockId) }
			.select { blocks, hierarchies in (blocks.id, hierarchies.pageId.unsafelyUnwrapped) }
			.fetchAll(db)
		for (target, children) in Dictionary(grouping: children, by: \.1) {
			let ordering = try ParagraphOrder(parentId: target, in: db)
			let ranks = try ordering.appendRanks(count: children.count, in: db)
			for ((id, _), rank) in zip(children, ranks) {
				try Block.find(id).update {
					$0.parentId = #bind(target)
					$0.order = #bind(rank)
				}.execute(db)
			}
		}
		return merges
	}
}
