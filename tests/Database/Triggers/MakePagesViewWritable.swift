import Testing
import CustomDump
import Foundation
@testable import LatticeDev
import SQLiteData
import DependenciesTestSupport

extension Tests {
	@Suite("Database/Triggers/MakePagesViewWritable", .dependencies { try $0.bootstrapDatabase() })
	struct MakePagesViewWritableTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.MakePagesViewWritableTest {
	@Test("Inserting into Pages preserves the page fields in Block")
	func canInsertIntoPages() throws {
		let day = DayOfYear(day: 3, month: 2, year: 2026)
		let date = Date(timeIntervalSince1970: 1_770_076_800)
		let page = Page(id: UUID(100), title: day.rawValue, dailyNoteDate: day,
			props: "{\"color\":\"blue\"}", createdAt: date, updatedAt: date)
		try database.write { db in
			expectNoDifference(try Page.insert { page }.returning(\.self).fetchOne(db), page)
			expectNoDifference(try Block.find(page.id).fetchOne(db), Block(
				id: page.id, title: day.rawValue, dailyNoteDate: day,
				props: "{\"color\":\"blue\"}", createdAt: date, updatedAt: date
			))
			expectNoDifference(try BlockHierarchy.find(page.id).fetchOne(db)?.pageId, page.id)
		}
	}

	@Test("Deleting a page hides its subtree and retains the local indexes")
	func deletingPageHidesSubtree() throws {
		let (page, paragraph, child) = try database.write { db in
			let page = try #require(try Page.insert { Page(title: "Subtree Root") }.returning(\.self).fetchOne(db))
			let paragraph = try #require(try Paragraph.insert {
				Paragraph(string: "Paragraph [[Subtree Root]]", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))
			let child = try #require(try Paragraph.insert {
				Paragraph(string: "Child", parentId: paragraph.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			return (page, paragraph, child)
		}

		try database.write { db in
			try Page.find(page.id).delete().execute(db)
		}

		let (blocks, ancestors, references) = try database.read { db in
			(
				try Block.where { $0.id.in([page.id, paragraph.id, child.id]) }.fetchCount(db),
				try Ancestor.where { $0.blockId.in([paragraph.id, child.id]) }.fetchCount(db),
				try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchCount(db)
			)
		}
		#expect(try database.read { try Page.find(page.id).fetchOne($0) } == nil)
		expectNoDifference(try database.read { try Block.find(page.id).fetchOne($0)?.deletedAt }, Date(timeIntervalSince1970: 1_000))
		expectNoDifference(blocks, 3)
		expectNoDifference(ancestors, 3)
		expectNoDifference(references, 1)
		#expect(try database.read { try Paragraph.fetchCount($0) } == 0)
		#expect(try database.read { try Block.find(child.id).fetchOne($0)?.deletedAt } == nil)
	}
}
