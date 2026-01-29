import SQLiteData

@Table("grdb_migrations")
struct MigrationRecord: Sendable {
	let identifier: String
}
