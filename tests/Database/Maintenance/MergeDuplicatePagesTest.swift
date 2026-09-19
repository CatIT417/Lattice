import Testing
import SQLite3
import CustomDump
import Foundation
@testable import LatticeDev
import SQLiteData
import DependenciesTestSupport

extension Tests {
	@Suite("Database/Maintenance/MergeDuplicatePages", .dependencies {
		try $0.bootstrapDatabase()
		$0.date = .constant(.distantPast)
	})
	struct MergeDuplicatePagesTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.MergeDuplicatePagesTest {
	@Test("The smallest ID keeps all descendants regardless of insertion and creation order")
	func mergingDuplicatePageMovesParagraphsIntoSmallestID() throws {
		try database.write { db in
			let keeper = Block(id: UUID(100), title: "Duplicate Title", createdAt: Date(timeIntervalSince1970: 200))
			let loser = Block(id: UUID(101), title: "Duplicate Title", createdAt: Date(timeIntervalSince1970: 100))
			let root = Block(id: UUID(102), string: "Root", parentId: loser.id)
			let child = Block(id: UUID(103), string: "Child", parentId: root.id)
			try Block.insert { [loser, keeper, root, child] }.execute(db)
			expectNoDifference(try MergeDuplicatePages.run(in: db), [.init(loser: loser.id, keeper: keeper.id)])
			expectNoDifference(try Page.where { $0.canonicalTitle.eq("Duplicate Title") }.select(\.id).fetchAll(db), [keeper.id])
			let movedRoot = try #require(try Paragraph.find(root.id).fetchOne(db))
			let movedChild = try #require(try Paragraph.find(child.id).fetchOne(db))
			expectNoDifference(movedRoot.parentId, keeper.id)
			expectNoDifference(movedRoot.pageId, keeper.id)
			expectNoDifference(movedChild.parentId, root.id)
			expectNoDifference(movedChild.pageId, keeper.id)
		}
	}

	@Test("Rename collisions retain every child under the smallest page ID", arguments: [2, 3])
	func renamedPagesAreMerged(pageCount: Int) throws {
		try database.write { db in
			let pages = (0..<pageCount).map { Page(id: UUID(100 + $0), title: $0 == 0 ? "Shared Title" : "Other \($0)") }
			let paragraphs = pages.enumerated().map { index, page in
				Paragraph(id: UUID(200 + index), string: "Child \(index)", parentId: page.id, pageId: page.id, order: 0)
			}
			try Page.insert { pages }.execute(db)
			try Paragraph.insert { paragraphs }.execute(db)
			for page in pages.dropFirst() {
				try Block.find(page.id).update { $0.title = #bind("Shared Title") }.execute(db)
			}
			expectNoDifference(try MergeDuplicatePages.run(in: db), pages.dropFirst().map {
				MergeDuplicatePages.Merge(loser: $0.id, keeper: pages[0].id)
			})
			expectNoDifference(try Page.select(\.id).fetchAll(db), [pages[0].id])
			let attached = try Paragraph.order(by: \.id).fetchAll(db)
			expectNoDifference(attached.map(\.id), paragraphs.map(\.id))
			for paragraph in attached {
				expectNoDifference(paragraph.parentId, pages[0].id)
				expectNoDifference(paragraph.pageId, pages[0].id)
			}
		}
	}

	@Test("Merging a duplicate Page resolves the same reference key")
	func mergingReferencedDuplicateRepointsReference() throws {
		let (keeper, duplicatePage, paragraph, reference) = try database.write { db in
			let keeper = try Page.insert {
				Page(title: "Keeper Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}
			.returning(\.self)
			.fetchOne(db)!

			let duplicatePage = try Page.insert {
				Page(title: "Duplicate Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}
			.returning(\.self)
			.fetchOne(db)!

			let hostPage = try Page.insert {
				Page(title: "Host Page", createdAt: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 200))
			}
			.returning(\.self)
			.fetchOne(db)!

			let paragraph = try Paragraph.insert {
				Paragraph(string: "See [[Duplicate Title]]", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}
			.returning(\.self)
			.fetchOne(db)!

			let reference = try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchOne(db)!

			return (keeper, duplicatePage, paragraph, reference)
		}

		expectNoDifference(reference.targetKey, duplicatePage.canonicalTitle)

		try database.write { db in
			try Block.find(keeper.id).update { $0.title = #bind("Duplicate Title") }.execute(db)
			try MergeDuplicatePages.run(in: db)
		}

		let pages = try database.read { db in
			try Page.where { $0.canonicalTitle.eq("Duplicate Title") }.fetchAll(db)
		}
		expectNoDifference(pages.map(\.id), [keeper.id])

		let (updatedParagraph, references) = try database.read { db in
			try (
				Paragraph.find(paragraph.id).fetchOne(db),
				Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
			)
		}

		try expectNoDifference(#require(updatedParagraph), paragraph)

		expectNoDifference(references, [reference])
		#expect(try database.read { try Backlink.fetchOne($0)?.toBlock } == keeper.id)
	}

	@Test("Merging pages appends their children in order")
	func mergingPagesPreservesSiblingOrder() async throws {
		let (keeper, duplicatePage) = try await database.write { db in
			let keeper = try Page.insert {
				Page(title: "Shared Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}
			.returning(\.self)
			.fetchOne(db)!

			let duplicatePage = try Page.insert {
				Page(title: "Other Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}
			.returning(\.self)
			.fetchOne(db)!

			try Paragraph.insert {
				for order in 0 ..< 3 {
					Paragraph(string: "Keeper \(order)", parentId: keeper.id, pageId: keeper.id, order: order)
				}

				for order in 0 ..< 3 {
					Paragraph(string: "Duplicate \(order)", parentId: duplicatePage.id, pageId: duplicatePage.id, order: order)
				}
			}
			.execute(db)

			return (keeper, duplicatePage)
		}

		try await database.write { db in
			try Block.find(duplicatePage.id).update { $0.title = #bind("Shared Title") }.execute(db)
			try MergeDuplicatePages.run(in: db)
			let rows = try Paragraph.where { $0.parentId.eq(keeper.id) }.order { ($0.order, $0.id) }.fetchAll(db)
			expectNoDifference(rows.map(\.string), ["Keeper 0", "Keeper 1", "Keeper 2", "Duplicate 0", "Duplicate 1", "Duplicate 2"])
			#expect(try Block.find(duplicatePage.id).fetchOne(db)?.mergedInto == keeper.id)
			#expect(try Block.find(duplicatePage.id).fetchOne(db)?.deletedAt == nil)
		}
	}

	@Test("Merge candidate work grows linearly with unrelated pages")
	func candidateWork() throws {
		try database.write { db in
			let keeper = Block(id: UUID(1), title: "Duplicate")
			let loser = Block(id: UUID(2), title: "Duplicate")
			let unrelated = (0..<512).map { Block(id: UUID(100 + $0), title: "Unrelated \($0)") }
			try Block.insert { [keeper, loser] + Array(unrelated.prefix(32)) }.execute(db)
			func mergeSteps() throws -> Int {
				try measuredSteps(in: db) {
					expectNoDifference(try MergeDuplicatePages.run(in: db), [.init(loser: loser.id, keeper: keeper.id)])
				}
			}
			let small = try mergeSteps()
			try Block.find(loser.id).update { $0.mergedInto = #bind(UUID?.none) }.execute(db)
			try Block.insert { Array(unrelated.dropFirst(32)) }.execute(db)
			let large = try mergeSteps()
			#expect(small > 0)
			#expect(large < small * 24)
		}
	}

	@Test("Duplicate daily notes merge and exclude deleted pages")
	func duplicateDateCandidates() throws {
		try database.write { db in
			let day = DayOfYear(day: 5, month: 9, year: 2026)
			let deleted = Block(id: UUID(1), title: day.rawValue, dailyNoteDate: day, deletedAt: Date(timeIntervalSince1970: 100))
			let keeper = Block(id: UUID(2), title: "September 5, 2026", dailyNoteDate: day)
			let loser = Block(id: UUID(3), title: day.rawValue, dailyNoteDate: day)
			let child = Block(id: UUID(4), string: "Daily", parentId: loser.id, order: 0)
			try Block.insert { [deleted, keeper, loser, child] }.execute(db)
			#expect(try MergeDuplicatePages.hasPendingWork(in: db))
			expectNoDifference(try MergeDuplicatePages.run(in: db), [.init(loser: loser.id, keeper: keeper.id)])
			#expect(try Block.find(child.id).fetchOne(db)?.parentId == keeper.id)
			#expect(try Block.find(deleted.id).fetchOne(db) == deleted)
			#expect(try !MergeDuplicatePages.hasPendingWork(in: db))
		}
	}

	@Test("Redirect children retain order with linear work", arguments: [false, true])
	func batchRedirectChildren(requiresRepair: Bool) throws {
		try database.write { db in
			var steps: [Int] = []
			for childCount in [16, 128] {
				try db.inSavepoint {
					let first = Block(id: UUID(1), title: "First Page")
					let second = Block(id: UUID(2), title: "Second Page")
					let alias = Block(id: UUID(3), title: first.title, mergedInto: first.id)
					let olderAlias = Block(id: UUID(4), title: first.title, mergedInto: alias.id)
					let otherAlias = Block(id: UUID(5), title: second.title, mergedInto: second.id)
					let existing = Block(id: UUID(6), string: "Existing", parentId: first.id,
						order: requiresRepair ? Int.max - ParagraphOrder.gap : 10 * ParagraphOrder.gap)
					let moved = (0 ..< childCount).map { index in
						Block(id: UUID(100 + index), string: "Moved \(index)",
							parentId: index < childCount / 2 ? alias.id : olderAlias.id, order: index / 2,
							deletedAt: index == 7 ? Date(timeIntervalSince1970: 100) : nil)
					}
					let nested = Block(id: UUID(1000), string: "Nested", parentId: moved[0].id, order: 0)
					let other = Block(id: UUID(1001), string: "Other", parentId: otherAlias.id, order: 0)
					try Block.insert { [first, second, alias, olderAlias, otherAlias, existing] + moved + [nested, other] }.execute(db)
					steps.append(try measuredSteps(in: db) {
						expectNoDifference(try MergeDuplicatePages.run(in: db), [])
					})
					expectNoDifference(try Block.where { $0.parentId.eq(first.id) }.order { ($0.order, $0.id) }.select(\.id).fetchAll(db),
						[existing.id] + moved.map(\.id))
					#expect(try Block.find(moved[7].id).fetchOne(db)?.deletedAt == moved[7].deletedAt)
					#expect(try Paragraph.find(moved[7].id).fetchOne(db) == nil)
					#expect(try Paragraph.find(nested.id).fetchOne(db)?.parentId == moved[0].id)
					#expect(try Paragraph.find(nested.id).fetchOne(db)?.pageId == first.id)
					#expect(try Block.find(other.id).fetchOne(db)?.parentId == second.id)
					#expect(try !MergeDuplicatePages.hasPendingWork(in: db))
					let changes = db.totalChangesCount
					expectNoDifference(try MergeDuplicatePages.run(in: db), [])
					#expect(db.totalChangesCount == changes)
					return .rollback
				}
			}
			#expect(steps[0] > 0)
			#expect(steps[1] < steps[0] * 16)
		}
	}
}

private func measuredSteps(in db: Database, operation: () throws -> Void) rethrows -> Int {
	var steps = 0
	try withUnsafeMutablePointer(to: &steps) { counter in
		sqlite3_progress_handler(db.sqliteConnection, 1, { context in
			context!.assumingMemoryBound(to: Int.self).pointee += 1
			return 0
		}, counter)
		defer { sqlite3_progress_handler(db.sqliteConnection, 0, nil, nil) }
		try operation()
	}
	return steps
}
