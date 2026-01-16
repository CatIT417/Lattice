import GRDB
import Foundation
import SQLiteData

nonisolated protocol Migration: Sendable {
	static func run(_ db: Database) throws
}

nonisolated protocol Seeder: Sendable {
	typealias Records = [any StructuredQueriesCore.Table]

	static func seed() -> Records
}

extension Seeder {
	static func run(_ db: Database) throws {
		try db.seed { seed() }
	}

	static func apply(_ generators: [() -> Records]) -> Records {
		var records: Records = []

		for generator in generators {
			records.append(contentsOf: generator())
		}

		return records
	}
}

protocol DatabaseView: Sendable {
	static func create(in database: Database) throws
}

protocol Trigger: Sendable {
	static func install(in database: Database) throws
}

extension DatabaseMigrator {
	mutating func registerMigration<T: Migration>(_ migration: T.Type) {
		registerMigration(String(describing: migration)) { db in
			try migration.run(db)
		}
	}

	mutating func migrate(_ migrations: [Migration.Type], in database: any DatabaseWriter) throws {
		registerMigrations(migrations)
		try migrate(database)
	}

	mutating func registerMigrations(_ migrations: [Migration.Type]) {
		for migration in migrations {
			registerMigration(migration)
		}
	}
}

extension GRDB.TableDefinition {
	@discardableResult
	func primaryUUID(_ name: String) -> ColumnDefinition {
		column(name, .text).primaryKey(onConflict: .replace).notNull().defaults(sql: "(uuid())")
	}

	@discardableResult
	func id() -> ColumnDefinition {
		primaryUUID("id")
	}

	func constraint(_ sql: SQLQueryExpression<Bool>) {
		constraint(sql: sql.queryFragment.segments.reduce(into: "") { string, segment in
			switch segment {
				case let .sql(sql): string.append(sql)
				case .binding: string.append("?")
			}
		})
	}
}

extension DatabaseWriter {
	func setupViews(_ views: [DatabaseView.Type]) throws {
		try write { database in
			for view in views {
				try view.create(in: database)
			}
		}
	}

	func setupTriggers(_ triggers: [Trigger.Type]) throws {
		try write { database in
			for trigger in triggers {
				try trigger.install(in: database)
			}
		}
	}

	func seed<T: Seeder>(_: T.Type) throws {
		try write { database in
			try database.seed(T.seed)
		}
	}
}
