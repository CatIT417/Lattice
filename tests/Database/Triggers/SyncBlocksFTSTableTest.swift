import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SyncBlocksFTSTable", .dependencies { try $0.bootstrapDatabase() })
	struct SyncBlocksFTSTableTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.SyncBlocksFTSTableTest {
	@Test("Inserting a Page creates a corresponding FTS row with its title")
	func insertingPageCreatesFTSRow() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db)
		})

		let ftsRow = try #require(database.read { db in
			try BlockText.where { $0.blockID.eq(page.id) }.fetchOne(db)
		})

		#expect(ftsRow.title == "Test Page")
		#expect(ftsRow.string == nil)
	}

	@Test("Inserting a Paragraph creates a corresponding FTS row with its string")
	func insertingParagraphCreatesFTSRow() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Host Page") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Hello world", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let ftsRow = try #require(database.read { db in
			try BlockText.where { $0.blockID.eq(paragraph.id) }.fetchOne(db)
		})

		#expect(ftsRow.title == nil)
		#expect(ftsRow.string == "Hello world")
	}

	@Test("Updating a Page title updates the FTS row")
	func updatingPageTitleUpdatesFTSRow() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Old Title") }.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(page.id).update { $0.title = #bind("New Title") }.execute(db)
		}

		let ftsRow = try #require(database.read { db in
			try BlockText.where { $0.blockID.eq(page.id) }.fetchOne(db)
		})

		#expect(ftsRow.title == "New Title")
	}

	@Test("Updating a Paragraph string updates the FTS row")
	func updatingParagraphStringUpdatesFTSRow() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Host Page") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "original text", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(paragraph.id).update { $0.string = #bind("updated text") }.execute(db)
		}

		let ftsRow = try #require(database.read { db in
			try BlockText.where { $0.blockID.eq(paragraph.id) }.fetchOne(db)
		})

		#expect(ftsRow.string == "updated text")
	}

	@Test("Deleting a Block removes the FTS row")
	func deletingBlockRemovesFTSRow() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Doomed Page") }.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Page.find(page.id).delete().execute(db)
		}

		let ftsRow = try database.read { db in
			try BlockText.where { $0.blockID.eq(page.id) }.fetchOne(db)
		}

		#expect(ftsRow == nil)
	}

	@Test("FTS match query finds blocks by title")
	func ftsMatchFindsBlocksByTitle() throws {
		try database.write { db in
			try Page.insert { Page(title: "Quantum Mechanics") }.execute(db)
			try Page.insert { Page(title: "Classical Physics") }.execute(db)
		}

		let results = try database.read { db in
			try Block
				.join(BlockText.all) { $0.id.eq($1.blockID) }
				.where { $1.match("Quantum".quoted()) }
				.select { block, _ in block }
				.fetchAll(db)
		}

		#expect(results.count == 1)
		#expect(results.first?.title == "Quantum Mechanics")
	}

	@Test("FTS match query finds blocks by paragraph text")
	func ftsMatchFindsBlocksByParagraphText() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Notes") }.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "photosynthesis is fascinating", parentId: page.id, pageId: page.id, order: 0)
				Paragraph(string: "gravity pulls things down", parentId: page.id, pageId: page.id, order: 1)
			}.execute(db)
		}

		let results = try database.read { db in
			try Block
				.join(BlockText.all) { $0.id.eq($1.blockID) }
				.where { $1.match("photosynthesis".quoted()) }
				.select { block, _ in block }
				.fetchAll(db)
		}

		#expect(results.count == 1)
		#expect(results.first?.string == "photosynthesis is fascinating")
	}
}
