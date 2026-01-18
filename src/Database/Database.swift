import SQLiteData
import Foundation

fileprivate nonisolated let logger = Logger(category: "Database")

func appDatabase() throws -> any DatabaseWriter {
	@Dependency(\.isDebug) var isDebug
	@Dependency(\.context) var context

	let configuration = tap(Configuration()) { config in
		config.foreignKeysEnabled = true
		config.prepareDatabase { db in
			try db.setupViews([
				CreatePagesView.self,
				CreateParagraphsView.self,
				CreateBacklinksView.self,
			])

			#if DEBUG
			db.trace(options: .profile) {
				logger.debug("\($0.expandedDescription)")
			}
			#endif
		}
	}

	let database = try defaultDatabase(configuration: configuration)
	logger.info("open '\(database.path)'")

	var migrator = DatabaseMigrator()
	#if DEBUG
	migrator.eraseDatabaseOnSchemaChange = true
	#endif

	try migrator.migrate([
		CreateBlocksTable.self,
		CreateReferencesTable.self,
		CreateAncestorsTable.self,
	], in: database, clean: isDebug)

	try database.setupTriggers([
		SyncAncestorsTable.self,
		MakePagesViewWritable.self,
		MakeParagraphsViewWritable.self,
	])

	#if DEBUG
	try database.seed(SeedDatabase.self)
	#endif

	return database
}
