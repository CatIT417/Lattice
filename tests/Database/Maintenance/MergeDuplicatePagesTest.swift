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
		@FetchAll(Paragraph.order(by: \.string)) var paragraphs
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.MergeDuplicatePagesTest {
	@Test("Merging a duplicate Page moves its Paragraphs into the oldest Page")
	func mergingDuplicatePageMovesParagraphsIntoOldest() throws {
		let (firstPage, duplicatePage, rootParagraph, childParagraph) = try database.write { db in
			let firstPage = try Page.insert {
				Page(title: "Duplicate Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}
			.returning(\.self)
			.fetchOne(db)!

			let duplicatePage = try Page.insert {
				Page(title: "Duplicate Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}
			.returning(\.self)
			.fetchOne(db)!

			let rootParagraph = try Paragraph.insert {
				Paragraph(string: "Root", parentId: duplicatePage.id, pageId: duplicatePage.id, order: 0)
			}
			.returning(\.self)
			.fetchOne(db)!

			let childParagraph = try Paragraph.insert {
				Paragraph(string: "Child", parentId: rootParagraph.id, pageId: duplicatePage.id, order: 0)
			}
			.returning(\.self)
			.fetchOne(db)!

			return (firstPage, duplicatePage, rootParagraph, childParagraph)
		}

		let merges = try database.write { try MergeDuplicatePages.run(in: $0) }
		expectNoDifference(merges, [.init(loser: duplicatePage.id, keeper: firstPage.id)])

		let pages = try database.read { db in
			try Page.where { $0.title.eq("Duplicate Title") }.fetchAll(db)
		}
		expectNoDifference(pages.map(\.id), [firstPage.id])

		let updatedRoot = try #require(database.read { db in
			try Paragraph.find(rootParagraph.id).fetchOne(db)
		})
		expectNoDifference(updatedRoot.pageId, firstPage.id)
		expectNoDifference(updatedRoot.parentId, firstPage.id)

		let updatedChild = try #require(database.read { db in
			try Paragraph.find(childParagraph.id).fetchOne(db)
		})
		expectNoDifference(updatedChild.pageId, firstPage.id)
		expectNoDifference(updatedChild.parentId, rootParagraph.id)
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
			try Page.where { $0.title.eq("Shared Title") }.fetchAll(db)
		}
		expectNoDifference(pages.map(\.id), [firstPage.id])

		let updatedRoot = try #require(database.read { db in
			try Paragraph.find(rootParagraph.id).fetchOne(db)
		})
		expectNoDifference(updatedRoot.pageId, firstPage.id)
		expectNoDifference(updatedRoot.parentId, firstPage.id)
	}

	@Test("Merging a referenced duplicate Page repoints the Reference")
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

		expectNoDifference(reference.targetBlockId, duplicatePage.id)

		try database.write { db in
			try Block.find(keeper.id).update { $0.title = #bind("Duplicate Title") }.execute(db)
			try MergeDuplicatePages.run(in: db)
		}

		let pages = try database.read { db in
			try Page.where { $0.title.eq("Duplicate Title") }.fetchAll(db)
		}
		expectNoDifference(pages.map(\.id), [keeper.id])

		let (updatedParagraph, references) = try database.read { db in
			try (
				Paragraph.find(paragraph.id).fetchOne(db),
				Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
			)
		}

		try expectNoDifference(#require(updatedParagraph), paragraph)

		var expectedReference = reference
		expectedReference.targetBlockId = keeper.id
		expectNoDifference(references, [expectedReference])
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
			try Page.where { $0.title.eq("Shared Title") }.fetchAll(db)
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

	@Test("Merging Pages with colliding Paragraph orders produces a gap-free order")
	func mergingPagesWithOrderCollisionsProducesGapFreeOrder() async throws {
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

		try await $paragraphs.load()

		await expectDifference($paragraphs) {
			try await database.write { db in
				try Block.find(duplicatePage.id).update { $0.title = #bind("Shared Title") }.execute(db)
				try MergeDuplicatePages.run(in: db)
			}
		} changes: { paragraphs in
			tap(&paragraphs[0]) {
				$0.pageId = keeper.id
				$0.parentId = keeper.id
				$0.order = 2
			}
			tap(&paragraphs[1]) {
				$0.pageId = keeper.id
				$0.parentId = keeper.id
			}
			tap(&paragraphs[2]) {
				$0.pageId = keeper.id
				$0.parentId = keeper.id
				$0.order = 0
			}
			tap(&paragraphs[3]) { $0.order = 3 }
			tap(&paragraphs[4]) { $0.order = 4 }
			tap(&paragraphs[5]) { $0.order = 5 }
		}

		expectNoDifference(paragraphs.map(\.order).sorted(), Array(0 ..< 6))
	}

	@Test("The keeper is the oldest Page, with the smallest id breaking ties")
	func keeperIsChosenByCreatedAtThenID() throws {
		let (first, second, third) = try database.write { db in
			let first = try Page.insert {
				Page(title: "Tie", createdAt: Date(timeIntervalSince1970: 50), updatedAt: Date(timeIntervalSince1970: 50))
			}
			.returning(\.self)
			.fetchOne(db)!

			let second = try Page.insert {
				Page(title: "Tie", createdAt: Date(timeIntervalSince1970: 50), updatedAt: Date(timeIntervalSince1970: 50))
			}
			.returning(\.self)
			.fetchOne(db)!

			let third = try Page.insert {
				Page(title: "Tie", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}
			.returning(\.self)
			.fetchOne(db)!

			return (first, second, third)
		}

		#expect(first.id < second.id)

		let merges = try database.write { try MergeDuplicatePages.run(in: $0) }
		expectNoDifference(merges, [
			.init(loser: first.id, keeper: third.id),
			.init(loser: second.id, keeper: third.id),
		])
	}

	@Test("Running the merge on an already merged database does nothing")
	func runIsIdempotent() throws {
		try database.write { db in
			try Page.insert {
				Page(title: "Shared Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
				Page(title: "Shared Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}
			.execute(db)
		}

		let first = try database.write { try MergeDuplicatePages.run(in: $0) }
		let second = try database.write { try MergeDuplicatePages.run(in: $0) }

		expectNoDifference(first.count, 1)
		expectNoDifference(second, [])
	}
}
