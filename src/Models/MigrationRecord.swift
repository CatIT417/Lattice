import SQLiteData

@Table("grdb_migrations")
struct MigrationRecord: Sendable {
	var identifier: String
}
