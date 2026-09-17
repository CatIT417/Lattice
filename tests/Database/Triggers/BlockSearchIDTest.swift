import GRDB
import SQLite3
import Testing
import Foundation
import SQLiteData
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Database/BlockSearchIDs")
	struct BlockSearchIDTest {
		let database: any DatabaseWriter

		init() throws {
			database = try makeDatabase()
			try database.write { db in
				try CreateBlocksTable.up(db)
				try CreateBlocksFTSTable.up(db)
			}
			try database.setupTriggers([SyncBlocksFTSTable.self])
		}
	}
}

extension Tests.BlockSearchIDTest {
	@Test("Search keys survive block row number changes and VACUUM")
	func vacuum() throws {
		let page = Block(title: "Notes")
		let paragraph = Block(string: "Original text", parentId: page.id)
		let before = try database.write { db in
			try Block.insert { [page, paragraph] }.execute(db)
			try #sql("UPDATE \(Block.self) SET rowid = rowid + 1000").execute(db)
			return try BlockSearchID.order(by: \.id).fetchAll(db)
		}

		try database.writeWithoutTransaction { db in
			try #sql("VACUUM").execute(db)
		}

		try database.write { db in
			try expectNoDifference(BlockSearchID.order(by: \.id).fetchAll(db), before)
			try Block.find(paragraph.id).update { $0.string = #bind("Updated text") }.execute(db)
			try expectNoDifference(BlockText.matching("Updated").select(\.blockID).fetchAll(db), [paragraph.id])
			#expect(try BlockText.matching("Original").fetchCount(db) == 0)
			try Block.find(paragraph.id).delete().execute(db)
			#expect(try BlockText.matching("Updated").fetchCount(db) == 0)
			try expectNoDifference(BlockSearchID.select(\.blockID).fetchAll(db), [page.id])
		}
	}

	@Test("Deletion markers, rollback, and reinsertion preserve search keys")
	func deletion() throws {
		let page = Block(title: "Original title")
		let before = try database.write { db in
			try Block.insert { page }.execute(db)
			try Block.find(page.id).update { $0.deletedAt = $now().asOptional }.execute(db)
			#expect(try BlockText.fetchCount(db) == 1)
			return try BlockSearchID.fetchAll(db)
		}

		try database.writeWithoutTransaction { db in
			try db.inTransaction {
				try Block.find(page.id).delete().execute(db)
				#expect(try BlockSearchID.fetchCount(db) == 0)
				#expect(try BlockText.fetchCount(db) == 0)
				return .rollback
			}
		}

		try database.write { db in
			try expectNoDifference(BlockSearchID.fetchAll(db), before)
			try expectNoDifference(BlockText.matching("Original").select(\.blockID).fetchAll(db), [page.id])
			try Block.find(page.id).delete().execute(db)
			try Block.insert { Block(id: page.id, title: "Replacement title") }.execute(db)
			try expectNoDifference(BlockSearchID.select(\.blockID).fetchAll(db), [page.id])
			try expectNoDifference(BlockText.matching("Replacement").select(\.blockID).fetchAll(db), [page.id])
			#expect(try BlockText.matching("Original").fetchCount(db) == 0)
		}
	}

	@Test("Rebuilds keep search keys and FTS rows in the same transaction")
	func rebuild() throws {
		let page = Block(id: UUID(100), title: "Original title")
		let other = Block(id: UUID(0), title: "Other title")
		let before = try database.write { db in
			try Block.insert { [page, other] }.execute(db)
			return try BlockSearchID.order(by: \.id).fetchAll(db)
		}

		try database.writeWithoutTransaction { db in
			try db.inTransaction {
				try Block.insert { Block(id: UUID(200), title: "Rolled back") }.execute(db)
				try RebuildSearchIndex.populate(in: db)
				return .rollback
			}
		}

		try database.write { db in
			try expectNoDifference(BlockSearchID.order(by: \.id).fetchAll(db), before)
			#expect(try BlockText.matching("Rolled").fetchCount(db) == 0)
			try RebuildSearchIndex.populate(in: db)
			try Block.find(page.id).update { $0.title = #bind("Updated title") }.execute(db)
			try expectNoDifference(BlockText.matching("Updated").select(\.blockID).fetchAll(db), [page.id])
			#expect(try BlockText.matching("Original").fetchCount(db) == 0)
			try Block.find(page.id).delete().execute(db)
			try expectNoDifference(BlockSearchID.select(\.blockID).fetchAll(db), [other.id])
			try expectNoDifference(BlockText.select(\.blockID).fetchAll(db), [other.id])
		}
	}

	@Test("The FTS migration creates search keys without changes to blocks")
	func migration() throws {
		let database = try makeDatabase()
		var migrator = DatabaseMigrator()
		migrator.registerMigration("CreateBlocksTable") { try CreateBlocksTable.up($0) }
		try migrator.migrate(database)
		let page = Block(title: "Original title")
		let before = try database.write { db in
			try Block.insert { page }.execute(db)
			return try Block.fetchAll(db)
		}

		migrator.registerMigration("CreateBlocksFTSTable") { try CreateBlocksFTSTable.up($0) }
		try migrator.migrate(database)
		try database.setupTriggers([SyncBlocksFTSTable.self])
		try database.write { db in
			try expectNoDifference(Block.fetchAll(db), before)
			try expectNoDifference(BlockSearchID.select(\.blockID).fetchAll(db), [page.id])
			try expectNoDifference(BlockText.matching("Original").select(\.blockID).fetchAll(db), [page.id])
			try Block.find(page.id).update { $0.title = #bind("Updated title") }.execute(db)
			try expectNoDifference(BlockText.matching("Updated").select(\.blockID).fetchAll(db), [page.id])
		}
	}

	@Test("FTS update and delete work does not grow with the block count")
	func lookupCost() throws {
		try database.write { db in
			let page = Block(title: "Target title")
			try Block.insert { page }.execute(db)
			func steps(_ query: some StructuredQueriesCore.Statement<Void>) throws -> Int32 {
				let (sql, _) = query.query.prepare { _ in "?" }
				let statement = try db.cachedStatement(sql: sql)
				sqlite3_stmt_status(statement.sqliteStatement, SQLITE_STMTSTATUS_VM_STEP, 1)
				try query.execute(db)
				return sqlite3_stmt_status(statement.sqliteStatement, SQLITE_STMTSTATUS_VM_STEP, 0)
			}

			let update = Block.find(page.id).update { $0.title = #bind("Updated title") }
			let delete = Block.find(page.id).delete()
			let smallUpdate = try steps(update)
			let smallDelete = try steps(delete)
			try Block.insert { page }.execute(db)
			try Block.insert { (0..<1000).map { _ in Block(title: "Other title") } }.execute(db)
			let largeUpdate = try steps(update)
			let largeDelete = try steps(delete)

			#expect(largeUpdate < smallUpdate * 4)
			#expect(largeDelete < smallDelete * 4)
		}
	}
}
