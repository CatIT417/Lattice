import SQLiteData

final class CreateReferencesTable: Migration {
	static func up(_ db: Database) throws {
		// Links between blocks (the [[wiki links]] and ((block refs)))
		try db.create(table: "blockReferences") { table in
			table.column("sourceBlockId", .text).notNull()
			table.column("kind", .text).notNull() // 'page_link', 'block_ref', 'block_embed', 'tag'
			table.column("targetKey", .text).notNull()
			table.primaryKey(["sourceBlockId", "kind", "targetKey"])
		}

		try db.create(indexOn: "blockReferences", columns: ["kind", "targetKey", "sourceBlockId"])
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "blockReferences")
	}
}
