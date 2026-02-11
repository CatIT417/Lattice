import Testing
import SQLiteData
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/MakePagesViewWritable")
	struct MakePagesViewWritableTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.MakePagesViewWritableTest {
	@Test("Inserting into the Pages view creates the corresponding Block")
	func canInsertIntoPages() throws {
		let props = "{\"color\":\"blue\"}"
		// `dailyNoteDate` is persisted as a day-only ISO string (YYYY-MM-DD).
		// Use a canonical UTC midnight value to keep this assertion timezone-stable.
		let date = Date(timeIntervalSince1970: 1_770_076_800)

		let page = try #require(database.write { db in
			try Page.insert {
				Page(title: "Test Page", dailyNoteDate: date, props: props, createdAt: date, updatedAt: date)
			}.returning(\.self).fetchOne(db)
		})

		let block = try #require(database.read { db in
			try Block.find(page.id).fetchOne(db)
		})

		expectNoDifference(page.props, props)
		expectNoDifference(page.createdAt, date)
		expectNoDifference(page.updatedAt, date)
		expectNoDifference(page.dailyNoteDate, date)

		expectNoDifference(page.id, block.id)
		expectNoDifference(page.title, block.title)
		expectNoDifference(page.props, block.props)
		expectNoDifference(page.createdAt, block.createdAt)
		expectNoDifference(page.updatedAt, block.updatedAt)
		expectNoDifference(page.dailyNoteDate, block.dailyNoteDate)

		expectNoDifference(block.order, 0)
		expectNoDifference(block.string, nil)
		expectNoDifference(block.pageId, nil)
		expectNoDifference(block.isOpen, true)
		expectNoDifference(block.heading, nil)
		expectNoDifference(block.parentId, nil)
		expectNoDifference(block.textAlign, .left)
		expectNoDifference(block.viewType, .bullet)
	}

	@Test("Updating via the Pages view is not supported")
	func updateViaViewFails() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db)
		})

		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Page.find(page.id).update { $0.title = "Updated Title" }.execute(db)
			}
		}
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
