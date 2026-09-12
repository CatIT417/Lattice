import SQLiteData

final class CreateLocalGraphIndexes: Migration {
	static func up(_ db: Database) throws {
		try db.create(table: "blockHierarchy") { table in
			table.column("blockId", .text).notNull().primaryKey()
			table.column("pageId", .text)
			table.column("isVisible", .boolean).notNull()
		}
		try db.create(indexOn: "blockHierarchy", columns: ["pageId", "isVisible"])
		try db.create(indexOn: "blocks", columns: ["mergedInto"])
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "blockHierarchy")
	}
}
