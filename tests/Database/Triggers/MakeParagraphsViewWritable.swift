import Testing
import SQLiteData
import Foundation
import CustomDump

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
		let order = 2
		let isOpen = false
		let props = "{\"foo\":1}"
		let string = "My Paragraph"
		let heading = Block.HeadingLevel.h2
		let viewType = Block.ViewType.numbered
		let textAlign = Block.TextAlignment.right
		let date = Calendar.current.startOfDay(for: Date())

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: string, parentId: page.id, pageId: page.id, order: order, heading: heading, viewType: viewType, textAlign: textAlign, isOpen: isOpen, props: props, createdAt: date, updatedAt: date)
			}.returning(\.self).fetchOne(db)
		})

		let block = try #require(database.read { db in
			try Block.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(paragraph.order, order)
		expectNoDifference(paragraph.props, props)
		expectNoDifference(paragraph.isOpen, isOpen)
		expectNoDifference(paragraph.string, string)
		expectNoDifference(paragraph.createdAt, date)
		expectNoDifference(paragraph.updatedAt, date)
		expectNoDifference(paragraph.heading, heading)
		expectNoDifference(paragraph.viewType, viewType)
		expectNoDifference(paragraph.textAlign, textAlign)

		expectNoDifference(paragraph.id, block.id)
		expectNoDifference(paragraph.props, block.props)
		expectNoDifference(paragraph.order, block.order)
		expectNoDifference(paragraph.string, block.string)
		expectNoDifference(paragraph.pageId, block.pageId)
		expectNoDifference(paragraph.isOpen, block.isOpen)
		expectNoDifference(paragraph.heading, block.heading)
		expectNoDifference(paragraph.parentId, block.parentId)
		expectNoDifference(paragraph.viewType, block.viewType)
		expectNoDifference(paragraph.textAlign, block.textAlign)
		expectNoDifference(paragraph.createdAt, block.createdAt)
		expectNoDifference(paragraph.updatedAt, block.updatedAt)

		expectNoDifference(block.title, nil)
		expectNoDifference(block.dailyNoteDate, nil)
	}

	@Test("Updating via the Paragraphs view is not supported")
	func updateViaViewFails() throws {
		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "My Paragraph", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Paragraph.find(paragraph.id).update { $0.string = "Updated Paragraph" }.execute(db)
			}
		}
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
