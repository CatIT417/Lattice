import GRDB
import SQLiteData

final class CreateBlocksFTSTable: Migration {
	static func up(_ db: Database) throws {
		try db.create(virtualTable: "blockTexts", using: GRDB.FTS5()) { table in
			table.column("blockID").notIndexed()
			table.column("title")
			table.column("string")
			table.tokenizer = .init(components: ["trigram"])
		}

		let existingBlocks = try Block.all.select {
			BlockText.Columns(blockID: $0.id, title: $0.title, string: $0.string)
		}.fetchAll(db)

		try BlockText.insert { existingBlocks }.execute(db)
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "blockTexts")
	}
}
