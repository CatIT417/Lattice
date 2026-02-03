import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite(.dependency(\.date, .constant(.distantPast)))
	struct UpdateParagraphOrderTest {
		@FetchAll var paragraphs: [Paragraph]
		@Dependency(\.uuid) var uuid
		@Dependency(\.defaultDatabase) var database

		let page: Page

		init() throws {
			page = try #require(_database.wrappedValue.write { db in
				try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db)
			})
		}
	}
}

extension Tests.UpdateParagraphOrderTest {
	@Test("Inserting a Paragraph updates the order of sibling Paragraphs after it")
	func insertingMovesSiblings() async throws {
		try await database.write { db in
			try Paragraph.insert {
				for i in 0..<5 {
					Paragraph(string: "Paragraph \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.execute(db)
		}
		try await $paragraphs.load()

		let newParagraphID = uuid()

		await expectDifference($paragraphs) {
			try await database.write { db in
				try Paragraph.insert {
					Paragraph(id: newParagraphID, string: "New Paragraph", parentId: page.id, pageId: page.id, order: 2)
				}.execute(db)
			}
		} changes: { paragraphs in
			for i in paragraphs.indices {
				if paragraphs[i].order >= 2 {
					paragraphs[i].order += 1
				}
			}

			paragraphs.append(Paragraph(id: newParagraphID, string: "New Paragraph", parentId: page.id, pageId: page.id, order: 2))
		}
	}

	@Test("Updating a Paragraph's order updates the order of sibling Paragraphs accordingly")
	func updatingOrderMovesSiblings() async throws {
		try await database.write { db in
			try Paragraph.insert {
				for i in 0..<5 {
					Paragraph(string: "Paragraph \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.execute(db)
		}
		try await $paragraphs.load()

		await expectDifference($paragraphs) {
			try await database.write { db in
				try Block.find(paragraphs[3].id).update {
					$0.order = 1
				}.execute(db)
			}
		} changes: { paragraphs in
			for i in paragraphs.indices {
				if i == 3 { paragraphs[i].order = 1 }
				else if i < 3, paragraphs[i].order >= 1 { paragraphs[i].order += 1 }
			}
		}
	}

	@Test("Moving a Paragraph down shifts intervening siblings up")
	func movingDownShiftsSiblingsUp() async throws {
		try await database.write { db in
			try Paragraph.insert {
				for i in 0..<5 {
					Paragraph(string: "Paragraph \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.execute(db)
		}
		try await $paragraphs.load()

		await expectDifference($paragraphs) {
			try await database.write { db in
				try Block.find(paragraphs[1].id).update {
					$0.order = 3
				}.execute(db)
			}
		} changes: { paragraphs in
			paragraphs[1].order = 3
			paragraphs[2].order -= 1
			paragraphs[3].order -= 1
		}
	}

	@Test("Updating a Paragraph's order to the same value does nothing")
	func noOpOrderUpdateDoesNothing() async throws {
		try await database.write { db in
			try Paragraph.insert {
				for i in 0..<5 {
					Paragraph(string: "Paragraph \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.execute(db)
		}
		try await $paragraphs.load()

		let paragraphsBefore = paragraphs

		try await database.write { db in
			try Block.find(paragraphs[2].id).update {
				$0.order = paragraphs[2].order
			}.execute(db)
		}

		try await $paragraphs.load()

		expectNoDifference(paragraphs, paragraphsBefore)
	}

	@Test("Updating a Paragraph's parentId updates the order of sibling Paragraphs accordingly")
	func updatingParentMovesSiblings() async throws {
		let secondPage = try await database.write { db in
			try Paragraph.insert {
				for i in 0..<5 {
					Paragraph(string: "Paragraph \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.execute(db)

			let secondPage = try Page.insert { Page(title: "Another Page") }.returning(\.self).fetchOne(db)!
			try Paragraph.insert {
				for i in 0..<3 {
					Paragraph(string: "Paragraph \(i)", parentId: secondPage.id, pageId: secondPage.id, order: i)
				}
			}.execute(db)

			return secondPage
		}
		try await $paragraphs.load()

		await expectDifference($paragraphs) {
			try await database.write { db in
				try Block.find(paragraphs[3].id).update {
					$0.order = 0
					$0.parentId = secondPage.id
				}.execute(db)
			}
		} changes: { paragraphs in
			paragraphs[3].order = 0
			paragraphs[3].parentId = secondPage.id

			for i in paragraphs.indices {
				if paragraphs[i].pageId == page.id, paragraphs[i].order > 3 { paragraphs[i].order -= 1 }
				else if paragraphs[i].pageId == secondPage.id { paragraphs[i].order += 1 }
			}
		}
	}

	@Test("Moving a Paragraph to a new parent with an appended order does not shift new siblings")
	func moveToNewParentAppendingDoesNotShift() async throws {
		let secondPage = try await database.write { db in
			try Paragraph.insert {
				for i in 0..<4 {
					Paragraph(string: "Paragraph \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.execute(db)

			let secondPage = try Page.insert { Page(title: "Another Page") }.returning(\.self).fetchOne(db)!
			try Paragraph.insert {
				for i in 0..<3 {
					Paragraph(string: "Paragraph \(i)", parentId: secondPage.id, pageId: secondPage.id, order: i)
				}
			}.execute(db)

			return secondPage
		}
		try await $paragraphs.load()

		await expectDifference($paragraphs) {
			try await database.write { db in
				try Block.find(paragraphs[1].id).update {
					$0.order = 3
					$0.parentId = secondPage.id
				}.execute(db)
			}
		} changes: { paragraphs in
			paragraphs[1].order = 3
			paragraphs[1].parentId = secondPage.id

			for i in paragraphs.indices {
				if i != 1, paragraphs[i].pageId == page.id, paragraphs[i].order > 1 {
					paragraphs[i].order -= 1
				}
			}
		}
	}

	@Test("Deleting a Paragraph updates the order of sibling Paragraphs after it")
	func deletingBlockUpdatesSiblings() async throws {
		try await database.write { db in
			try Paragraph.insert {
				for i in 0..<5 {
					Paragraph(string: "Paragraph \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.execute(db)
		}
		try await $paragraphs.load()

		await expectDifference($paragraphs) {
			try await database.write { db in
				try Paragraph.find(paragraphs[2].id).delete().execute(db)
			}
		} changes: { paragraphs in
			paragraphs.remove(at: 2)

			for i in paragraphs.indices {
				if paragraphs[i].order > 2 {
					paragraphs[i].order -= 1
				}
			}
		}
	}
}
