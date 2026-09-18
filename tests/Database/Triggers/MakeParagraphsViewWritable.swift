import Testing
import CustomDump
import Foundation
@testable import LatticeDev
import SQLiteData
import DependenciesTestSupport

extension Tests {
	@Suite("Database/Triggers/MakeParagraphsViewWritable", .dependencies { try $0.bootstrapDatabase() })
	struct MakeParagraphsViewWritableTest {
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
	@Test("Inserting into Paragraphs preserves all stored fields")
	func canInsertIntoParagraphs() throws {
		let date = Date(timeIntervalSince1970: 100)
		let paragraph = Paragraph(id: UUID(100), string: "My Paragraph", parentId: page.id,
			pageId: page.id, order: 7, heading: .h2, viewType: .numbered, textAlign: .right,
			isOpen: false, props: "{\"foo\":1}", createdAt: date, updatedAt: date)
		try database.write { db in
			expectNoDifference(try Paragraph.insert { paragraph }.returning(\.self).fetchOne(db), paragraph)
			expectNoDifference(try Block.find(paragraph.id).fetchOne(db), Block(
				id: paragraph.id, string: "My Paragraph", parentId: page.id, order: 7,
				heading: .h2, viewType: .numbered, textAlign: .right, isOpen: false,
				props: "{\"foo\":1}", createdAt: date, updatedAt: date
			))
			expectNoDifference(try BlockHierarchy.find(paragraph.id).fetchOne(db)?.pageId, page.id)
		}
	}

	@Test("Deleting a paragraph sets its deletion marker")
	func canDeleteFromParagraphs() throws {
		let paragraph = try #require(database.write { db in
			try Paragraph.insert { Paragraph(string: "My Paragraph", parentId: page.id, pageId: page.id, order: 0) }.returning(\.self).fetchOne(db)
		})

		let blockExists = try database.read { db in
			try Select(Block.find(paragraph.id).exists()).fetchOne(db)
		}
		#expect(blockExists == true)

		try database.write { db in
			try Paragraph.find(paragraph.id).delete().execute(db)
		}

		let blockExistsAfterDelete = try database.read { db in
			try Select(Block.find(paragraph.id).exists()).fetchOne(db)
		}
		#expect(blockExistsAfterDelete == true)
		#expect(try database.read { try Paragraph.find(paragraph.id).fetchOne($0) } == nil)
		#expect(try database.read { try Block.find(paragraph.id).fetchOne($0)?.deletedAt } != nil)
	}
}
