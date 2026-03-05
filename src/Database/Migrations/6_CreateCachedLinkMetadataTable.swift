import SQLiteData

final class CreateCachedLinkMetadataTable: Migration {
	static func up(_ db: Database) throws {
		try db.create(table: "linkMetadata") { table in
			table.column("url", .text).primaryKey()
			table.column("metadata", .blob).notNull()
		}
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "linkMetadata")
	}
}
