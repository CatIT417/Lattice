import Testing
import SQLiteData
import Foundation

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/TouchTimestamps")
	struct TouchTimestampsTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.TouchTimestampsTest {
	@Test("Block.updatedAt is updated on record update")
	func updatedAtIsTouchedOnUpdate() throws {
		let block = try #require(database.write { db in
			try Block.insert { Block(title: "Test Page") }.returning(\.self).fetchOne(db)
		})

		#expect(block.createdAt == block.updatedAt)

		try database.write { db in
			try Block.find(block.id).update { $0.title = "Updated Title" }.execute(db)
		}

		let updatedBlock = try database.read { db in
			try Block.find(block.id).fetchOne(db)
		}!

		#expect(block.updatedAt != updatedBlock.updatedAt)
	}

	@Test("A Page's updatedAt is updated when one of its child Blocks is updated")
	func pagesUpdatedAtIsTouchedOnChildUpdate() throws {
		let (page, children) = try #require(database.write { db in
			let page = try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db)!
			let childBlocks = try Paragraph.insert {
				(0...3).map { i in
					Paragraph(string: "Child Block \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.returning(\.self).fetchAll(db)

			return (page, childBlocks)
		})

		#expect(page.createdAt == page.updatedAt)

		let randomChild = try #require(children.randomElement())

		try database.write { db in
			try Block.find(randomChild.id).update { $0.string = "Updated Child Block" }.execute(db)
		}

		let updatedPage = try #require(database.read { db in
			try Page.find(page.id).fetchOne(db)
		})

		#expect(page.updatedAt != updatedPage.updatedAt)
	}
}
