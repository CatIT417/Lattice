import Testing
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

	@Test("Pages renamed to an existing title are merged")
	func renamedPagesAreMerged() throws {
		let (firstPage, secondPage, rootParagraph) = try database.write { db in
			let firstPage = try Page.insert {
				Page(title: "Shared Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}
			.returning(\.self)
			.fetchOne(db)!

			let secondPage = try Page.insert {
				Page(title: "Other Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}
			.returning(\.self)
			.fetchOne(db)!

			let rootParagraph = try Paragraph.insert {
				Paragraph(string: "Root", parentId: secondPage.id, pageId: secondPage.id, order: 0)
			}
			.returning(\.self)
			.fetchOne(db)!

			return (firstPage, secondPage, rootParagraph)
		}

		try database.write { db in
			try Block.find(secondPage.id).update { $0.title = #bind("Shared Title") }.execute(db)
			try MergeDuplicatePages.run(in: db)
		}

		let pages = try database.read { db in
			try Page.where { $0.canonicalTitle.eq("Shared Title") }.fetchAll(db)
		}
		expectNoDifference(pages.map(\.id), [firstPage.id])

		let updatedRoot = try #require(database.read { db in
			try Paragraph.find(rootParagraph.id).fetchOne(db)
		})
		expectNoDifference(updatedRoot.pageId, firstPage.id)
		expectNoDifference(updatedRoot.parentId, firstPage.id)
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

	@Test("Merging three Pages keeps one Page with all Paragraphs attached")
	func mergingThreePagesKeepsAllParagraphs() throws {
		let (firstPage, secondPage, thirdPage, paragraphIDs) = try database.write { db in
			let firstPage = try Page.insert {
				Page(title: "Shared Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}
			.returning(\.self)
			.fetchOne(db)!

			let secondPage = try Page.insert {
				Page(title: "Second Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}
			.returning(\.self)
			.fetchOne(db)!

			let thirdPage = try Page.insert {
				Page(title: "Third Title", createdAt: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 200))
			}
			.returning(\.self)
			.fetchOne(db)!

			let firstParagraph = try Paragraph.insert {
				Paragraph(string: "First", parentId: firstPage.id, pageId: firstPage.id, order: 0)
			}
			.returning(\.self)
			.fetchOne(db)!

			let secondParagraph = try Paragraph.insert {
				Paragraph(string: "Second", parentId: secondPage.id, pageId: secondPage.id, order: 0)
			}
			.returning(\.self)
			.fetchOne(db)!

			let thirdParagraph = try Paragraph.insert {
				Paragraph(string: "Third", parentId: thirdPage.id, pageId: thirdPage.id, order: 0)
			}
			.returning(\.self)
			.fetchOne(db)!

			return (firstPage, secondPage, thirdPage, [firstParagraph.id, secondParagraph.id, thirdParagraph.id])
		}

		let merges = try database.write { db in
			try Block.find(secondPage.id).update { $0.title = #bind("Shared Title") }.execute(db)
			try Block.find(thirdPage.id).update { $0.title = #bind("Shared Title") }.execute(db)
			return try MergeDuplicatePages.run(in: db)
		}

		expectNoDifference(merges, [
			.init(loser: secondPage.id, keeper: firstPage.id),
			.init(loser: thirdPage.id, keeper: firstPage.id),
		])

		let pages = try database.read { db in
			try Page.where { $0.canonicalTitle.eq("Shared Title") }.fetchAll(db)
		}
		expectNoDifference(pages.map(\.id), [firstPage.id])

		let attachedParagraphs = try database.read { db in
			try Paragraph.order(by: \.string).fetchAll(db)
		}

		expectNoDifference(Set(attachedParagraphs.map(\.id)), Set(paragraphIDs))
		for paragraph in attachedParagraphs {
			expectNoDifference(paragraph.pageId, firstPage.id)
			expectNoDifference(paragraph.parentId, firstPage.id)
		}
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

	@Test("Merge candidate query count stays bounded as unrelated pages increase", arguments: [0, 256])
	func boundedCandidateQueries(unrelatedCount: Int) throws {
		try database.write { db in
			let keeper = Block(id: UUID(1), title: "Duplicate")
			let loser = Block(id: UUID(2), title: "Duplicate")
			let unrelated = (0 ..< unrelatedCount).map {
				Block(id: UUID(100 + $0), title: "Unrelated \($0)")
			}
			try Block.insert { [keeper, loser] + unrelated }.execute(db)
			var pageReads: [String] = []
			db.trace(options: .profile) { event in
				if case let .profile(statement, _) = event,
				   statement.sql.hasPrefix("SELECT"), statement.sql.contains("FROM \"pages\"") {
					pageReads.append(statement.sql)
				}
			}
			defer { db.trace() }
			expectNoDifference(try MergeDuplicatePages.run(in: db), [.init(loser: loser.id, keeper: keeper.id)])
			#expect((1...2).contains(pageReads.count))
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

	@Test("Redirect children move in batches with bounded rank reads", arguments: [false, true])
	func batchRedirectChildren(requiresRepair: Bool) throws {
		try database.write { db in
			let first = Block(id: UUID(1), title: "First Page")
			let second = Block(id: UUID(2), title: "Second Page")
			let alias = Block(id: UUID(3), title: first.title, mergedInto: first.id)
			let olderAlias = Block(id: UUID(4), title: first.title, mergedInto: alias.id)
			let otherAlias = Block(id: UUID(5), title: second.title, mergedInto: second.id)
			let existing = Block(id: UUID(6), string: "Existing", parentId: first.id,
				order: requiresRepair ? Int.max - ParagraphOrder.gap : 10 * ParagraphOrder.gap)
			let moved = (0 ..< 40).map { index in
				Block(id: UUID(100 + index), string: "Moved \(index)",
					parentId: index < 20 ? alias.id : olderAlias.id, order: index / 2,
					deletedAt: index == 7 ? Date(timeIntervalSince1970: 100) : nil)
			}
			let nested = Block(id: UUID(200), string: "Nested", parentId: moved[0].id, order: 0)
			let other = Block(id: UUID(201), string: "Other", parentId: otherAlias.id, order: 0)
			try Block.insert { [first, second, alias, olderAlias, otherAlias, existing] + moved + [nested, other] }.execute(db)
			var rankReads = 0
			db.trace(options: .profile) { event in
				if case let .profile(statement, _) = event,
				   statement.sql.hasPrefix("SELECT \"blocks\".\"order\"") {
					rankReads += 1
				}
			}
			defer { db.trace() }
			expectNoDifference(try MergeDuplicatePages.run(in: db), [])
			#expect((1...5).contains(rankReads))
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
		}
	}
}
