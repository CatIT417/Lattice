import SQLiteData

final class CreateAncestorsTable: Migration {
	static func up(_ db: Database) throws {
		// Pre-computed ancestor relationships (like Roam's :block/parents)
		// This makes "find all descendants" and "find all ancestors" queries O(1)
		try db.create(table: "blockAncestors") { table in
			table.column("blockId", .text).notNull()
			table.column("ancestorId", .text).notNull().indexed()
			table.column("depth", .integer).notNull() // 1 = parent, 2 = grandparent, etc.

			table.constraint(#sql("CHECK (blockId != ancestorId)"))

			table.primaryKey(["blockId", "ancestorId"])
		}
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "blockAncestors")
	}
}
