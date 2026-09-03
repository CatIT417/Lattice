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
	@Test("Inserting into the Pages view creates the corresponding Block")
	func canInsertIntoPages() throws {
		let props = "{\"color\":\"blue\"}"
		let date = Date(timeIntervalSince1970: 1_770_076_800)
		let dailyNoteDate = DayOfYear(day: 3, month: 2, year: 2026)

		let page = try #require(database.write { db in
			try Page.insert {
				Page(title: "Test Page", dailyNoteDate: dailyNoteDate, props: props, createdAt: date, updatedAt: date)
			}
			.returning(\.self)
			.fetchOne(db)
		})

		let block = try #require(database.read { db in
			try Block.find(page.id).fetchOne(db)
		})

		expectNoDifference(page.props, props)
		expectNoDifference(page.createdAt, date)
		expectNoDifference(page.updatedAt, date)
		expectNoDifference(page.dailyNoteDate, dailyNoteDate)

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
			try Select(Block.find(page.id).exists()).fetchOne(db)
		}
		#expect(blockExists == true)

		try database.write { db in
			try Page.find(page.id).delete().execute(db)
		}

		let blockExistsAfterDelete = try database.read { db in
			try Select(Block.find(page.id).exists()).fetchOne(db)
		}
		#expect(blockExistsAfterDelete == false)
	}

	@Test("Deleting a page deletes its whole subtree and the subtree's derived rows")
	func deletingPageDeletesSubtree() throws {
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
		expectNoDifference(blocks, 0)
		expectNoDifference(ancestors, 0)
		expectNoDifference(references, 0)
	}

	@Test("Deleting a page also deletes paragraphs whose parent has not arrived")
	func deletingPageDeletesOrphanedParagraphs() throws {
		@Dependency(\.uuid) var uuid
		let missingParentID = uuid()

		let (page, orphan) = try database.write { db in
			let page = try #require(try Page.insert { Page(title: "Orphan Delete Root") }.returning(\.self).fetchOne(db))
			let orphan = try #require(try Paragraph.insert {
				Paragraph(string: "Orphan", parentId: missingParentID, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			return (page, orphan)
		}

		try database.write { db in
			try Page.find(page.id).delete().execute(db)
		}

		let orphanExists = try database.read { db in
			try Select(Block.find(orphan.id).exists()).fetchOne(db)
		}
		expectNoDifference(orphanExists, false)
	}
}
