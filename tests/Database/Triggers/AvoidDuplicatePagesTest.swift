import Testing
import SQLiteData
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	// TODO: Throughly check all edge cases that can occur when syncing.
	@Suite("Database/Triggers/AvoidDuplicatePages")
	struct AvoidDuplicatePagesTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.AvoidDuplicatePagesTest {
	@Test("Inserting a duplicate Page merges it into the oldest Page")
	func insertingDuplicatePageMergesIntoOldest() async throws {
		let (firstPage, duplicatePage, rootParagraph, childParagraph) = try await database.write { db in
			let firstPage = try Page.insert {
				Page(title: "Duplicate Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}.returning(\.self).fetchOne(db)!

			let duplicatePage = try Page.insert {
				Page(title: "Duplicate Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}.returning(\.self).fetchOne(db)!

			let rootParagraph = try Paragraph.insert {
				Paragraph(string: "Root", parentId: duplicatePage.id, pageId: duplicatePage.id, order: 0)
			}.returning(\.self).fetchOne(db)!

			let childParagraph = try Paragraph.insert {
				Paragraph(string: "Child", parentId: rootParagraph.id, pageId: duplicatePage.id, order: 0)
			}.returning(\.self).fetchOne(db)!

			return (firstPage, duplicatePage, rootParagraph, childParagraph)
		}

		let pages = try await waitForPages(title: "Duplicate Title", expectedCount: 1)
		#expect(pages.count == 1)

		let keeper = try #require(pages.first)
		expectNoDifference(keeper.id, firstPage.id)

		let duplicateExists = try await database.read { db in
			try Values(Page.find(duplicatePage.id).exists()).fetchOne(db)
		}
		#expect(duplicateExists == false)

		let updatedRoot = try #require(await database.read { db in
			try Paragraph.find(rootParagraph.id).fetchOne(db)
		})
		expectNoDifference(updatedRoot.pageId, firstPage.id)
		expectNoDifference(updatedRoot.parentId, firstPage.id)

		let updatedChild = try #require(await database.read { db in
			try Paragraph.find(childParagraph.id).fetchOne(db)
		})
		expectNoDifference(updatedChild.pageId, firstPage.id)
		expectNoDifference(updatedChild.parentId, rootParagraph.id)
	}

	@Test("Updating a Page title to an existing title merges pages")
	func updatingTitleMergesPages() async throws {
		let (firstPage, secondPage, rootParagraph) = try await database.write { db in
			let firstPage = try Page.insert {
				Page(title: "Shared Title", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
			}.returning(\.self).fetchOne(db)!

			let secondPage = try Page.insert {
				Page(title: "Other Title", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
			}.returning(\.self).fetchOne(db)!

			let rootParagraph = try Paragraph.insert {
				Paragraph(string: "Root", parentId: secondPage.id, pageId: secondPage.id, order: 0)
			}.returning(\.self).fetchOne(db)!

			return (firstPage, secondPage, rootParagraph)
		}

		try await database.write { db in
			try Block.find(secondPage.id).update { $0.title = "Shared Title" }.execute(db)
		}

		let pages = try await waitForPages(title: "Shared Title", expectedCount: 1)
		#expect(pages.count == 1)

		let keeper = try #require(pages.first)
		expectNoDifference(keeper.id, firstPage.id)

		let duplicateExists = try await database.read { db in
			try Values(Page.find(secondPage.id).exists()).fetchOne(db)
		}
		#expect(duplicateExists == false)

		let updatedRoot = try #require(await database.read { db in
			try Paragraph.find(rootParagraph.id).fetchOne(db)
		})
		expectNoDifference(updatedRoot.pageId, firstPage.id)
		expectNoDifference(updatedRoot.parentId, firstPage.id)
	}
}

extension Tests.AvoidDuplicatePagesTest {
	private func waitForPages(
		title: String,
		expectedCount: Int,
		timeout: TimeInterval = 1.0,
		pollInterval _: TimeInterval = 0.02
	) async throws -> [Page] {
		let deadline = Date().addingTimeInterval(timeout)
		var pages: [Page] = []

		while Date() < deadline {
			pages = try await database.read { db in
				try Page.where { $0.title == title }
					.order { $0.createdAt.asc() }
					.fetchAll(db)
			}

			if pages.count == expectedCount { return pages }
			try await Task.sleep(for: .seconds(0.5))
		}

		return pages
	}
}
