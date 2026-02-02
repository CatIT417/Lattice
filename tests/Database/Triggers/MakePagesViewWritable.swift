import Testing
import SQLiteData
import Foundation

@testable import LatticeDev

extension Tests {
	@Suite struct MakePagesViewWritableTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.MakePagesViewWritableTest {
	@Test("Inserting into the Pages view creates the corresponding Block")
	func canInsertIntoPages() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db)
		})

		let block = try #require(database.read { db in
			try Block.find(page.id).fetchOne(db)
		})

		#expect(page.id == block.id)
		#expect(page.title == block.title)
		#expect(page.props == block.props)
		#expect(page.createdAt == block.createdAt)
		#expect(page.updatedAt == block.updatedAt)
		#expect(page.dailyNoteDate == block.dailyNoteDate)

		#expect(block.order == 0)
		#expect(block.string == nil)
		#expect(block.pageId == nil)
		#expect(block.isOpen == true)
		#expect(block.heading == nil)
		#expect(block.parentId == nil)
		#expect(block.textAlign == .left)
		#expect(block.viewType == .bullet)
	}

	@Test("Deleting from the Pages view deletes the corresponding Block")
	func canDeleteFromPages() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db)
		})

		let blockExists = try database.read { db in
			try Values(Block.find(page.id).exists()).fetchOne(db)
		}
		#expect(blockExists == true)

		try database.write { db in
			try Page.find(page.id).delete().execute(db)
		}

		let blockExistsAfterDelete = try database.read { db in
			try Values(Block.find(page.id).exists()).fetchOne(db)
		}
		#expect(blockExistsAfterDelete == false)
	}
}
