import Testing
import SQLiteData
import Foundation

@testable import LatticeDev

extension Tests {
	@Suite struct MakeParagraphsViewWritableTest {
		@Dependency(\.defaultDatabase) var database

		let page: Page
		init() throws {
			page = try #require(_database.wrappedValue.write { db in
				try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db)
			})
		}
	}
}

extension Tests.MakeParagraphsViewWritableTest {
	@Test("Inserting into the Paragraphs view creates the corresponding Block")
	func canInsertIntoParagraphs() throws {
		let paragraph = try #require(database.write { db in
			try Paragraph.insert { Paragraph(string: "My Paragraph", parentId: page.id, pageId: page.id, order: 0) }.returning(\.self).fetchOne(db)
		})

		let block = try #require(database.read { db in
			try Block.find(paragraph.id).fetchOne(db)
		})

		#expect(paragraph.id == block.id)
		#expect(paragraph.props == block.props)
		#expect(paragraph.createdAt == block.createdAt)
		#expect(paragraph.updatedAt == block.updatedAt)
		#expect(paragraph.order == block.order)
		#expect(paragraph.string == block.string)
		#expect(paragraph.pageId == block.pageId)
		#expect(paragraph.isOpen == block.isOpen)
		#expect(paragraph.heading == block.heading)
		#expect(paragraph.parentId == block.parentId)
		#expect(paragraph.textAlign == block.textAlign)
		#expect(paragraph.viewType == block.viewType)

		#expect(block.title == nil)
		#expect(block.dailyNoteDate == nil)
	}

	@Test("Deleting from the Paragraphs view deletes the corresponding Block")
	func canDeleteFromParagraphs() throws {
		let paragraph = try #require(database.write { db in
			try Paragraph.insert { Paragraph(string: "My Paragraph", parentId: page.id, pageId: page.id, order: 0) }.returning(\.self).fetchOne(db)
		})

		let blockExists = try database.read { db in
			try Values(Block.find(paragraph.id).exists()).fetchOne(db)
		}
		#expect(blockExists == true)

		try database.write { db in
			try Paragraph.find(paragraph.id).delete().execute(db)
		}

		let blockExistsAfterDelete = try database.read { db in
			try Values(Block.find(paragraph.id).exists()).fetchOne(db)
		}
		#expect(blockExistsAfterDelete == false)
	}
}
