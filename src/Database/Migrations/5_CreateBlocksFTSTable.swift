import GRDB
import Foundation
import SQLiteData

final class CreateBlocksFTSTable: Migration {
	static func up(_ db: Database) throws {
		try db.create(virtualTable: "blockTexts", using: GRDB.FTS5()) { table in
			table.column("blockID").notIndexed()
			table.column("title")
			table.column("string")
			table.column("displayTitle")
			table.column("displayString")
			table.tokenizer = .init(components: ["trigram"])
		}

		try RebuildSearchIndex.populate(in: db)
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "blockTexts")
	}
}
