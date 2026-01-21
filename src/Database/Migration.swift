import GRDB
import Foundation
import SQLiteData

nonisolated protocol Migration: Sendable {
	static func up(_ db: Database) throws
	static func down(_ db: Database) throws
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
	static var uses: [any ScalarDatabaseFunction] { get }
}

extension Trigger {
	static var uses: [any ScalarDatabaseFunction] {
		[]
	}
}

extension DatabaseMigrator {
	mutating func registerMigration<T: Migration>(_ migration: T.Type) {
		registerMigration(String(describing: migration)) { db in
			try migration.up(db)
		}
	}

	mutating func migrate(_ migrations: [Migration.Type], in database: any DatabaseWriter, clean: Bool = false) throws {
		if clean {
			if let appliedMigrations = try? database.read({ try MigrationRecord.fetchAll($0) }) {
				try database.write { db in
					for migration in migrations {
						if appliedMigrations.contains(where: { $0.identifier == String(describing: migration) }) {
							try migration.down(db)
						}
					}
				}
			}
		}

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
	func setupTriggers(_ triggers: [Trigger.Type]) throws {
		try write { database in
			for trigger in triggers {
				for function in trigger.uses {
					database.add(function: function)
				}

				try trigger.install(in: database)
			}
		}
	}

	func seed<T: Seeder>(_: T.Type) throws {
		@Dependency(\.context) var context

		if context == .live {
			DispatchQueue.main.async {
				withErrorReporting {
					try self.write { database in
						try database.seed(T.seed)
					}
				}
			}
		} else {
			try write { database in
				try database.seed(T.seed)
			}
		}
	}
}

extension Database {
	func setupViews(_ views: [DatabaseView.Type]) throws {
		for view in views {
			try view.create(in: self)
		}
	}
}
