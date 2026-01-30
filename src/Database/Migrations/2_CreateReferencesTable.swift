import SQLiteData

final class CreateReferencesTable: Migration {
	static func up(_ db: Database) throws {
		// Links between blocks (the [[wiki links]] and ((block refs)))
		try db.create(table: "blockReferences") { table in
			table.id()
			table.column("sourceBlockId", .integer).notNull().indexed().references("blocks", column: "id", onDelete: .cascade)
			table.column("targetBlockId", .integer).notNull().indexed().references("blocks", column: "id", onDelete: .cascade)
			table.column("kind", .text).notNull() // 'page_link', 'block_ref', 'block_embed', 'tag'
			table.column("createdAt", .datetime).notNull().defaults(sql: "current_timestamp")

			// Uniqueness constraint (disabled for sync engine)
			// table.uniqueKey(["sourceBlockId", "targetBlockId", "kind"])
		}
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "blockReferences")
	}
}
