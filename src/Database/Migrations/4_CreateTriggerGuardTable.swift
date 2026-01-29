import SQLiteData

final class CreateTriggerGuardTable: Migration {
	static var isTemporary: Bool { true }

	static func up(_ db: Database) throws {
		try db.create(table: "_trigger_guard", temporary: true) { table in
			table.column("id", .integer).primaryKey(onConflict: .fail, autoincrement: false)
			table.column("depth", .integer).notNull().defaults(to: 0)

			table.constraint(sql: "CHECK (id = 0)")
		}

		try TriggerGuard.insert { TriggerGuard(depth: 0) }.execute(db)
	}

	static func down(_: Database) throws {
		//
	}
}
