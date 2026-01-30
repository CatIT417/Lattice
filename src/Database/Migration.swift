import GRDB
import Foundation
import SQLiteData

nonisolated protocol Migration: Sendable {
	static var isTemporary: Bool { get }

	static func up(_ db: Database) throws
	static func down(_ db: Database) throws
}

extension Migration {
	static var isTemporary: Bool {
		false
	}
}

nonisolated protocol Seeder: Sendable {
	typealias Records = [any StructuredQueriesCore.Table]

	@SeedsBuilder static func seed() -> Records
}

extension Seeder {
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
	mutating func migrate(_ migrations: [Migration.Type], in database: any DatabaseWriter) throws {
		registerMigrations(migrations.filter { !$0.isTemporary })

		try migrate(database)

		for migration in migrations.filter({ $0.isTemporary }) {
			try database.barrierWriteWithoutTransaction { db in
				try migration.up(db)
			}
		}
	}

	private mutating func registerMigrations(_ migrations: [Migration.Type]) {
		for migration in migrations {
			registerMigration(migration)
		}
	}

	private mutating func registerMigration<T: Migration>(_ migration: T.Type) {
		registerMigration(String(describing: migration)) { db in
			try migration.up(db)
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
		try barrierWriteWithoutTransaction { database in
			for trigger in triggers {
				for function in trigger.uses {
					database.add(function: function)
				}

				try trigger.install(in: database)
			}
		}
	}

	func seed<T: Seeder>(_: T.Type) throws {
		try write { db in
			try db.seed(T.seed)
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
