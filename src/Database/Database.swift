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

	try database.write { db in
		try #sql("PRAGMA recursive_triggers = OFF").execute(db)
	}

	try migrator.migrate([
		CreateBlocksTable.self,
		CreateReferencesTable.self,
		CreateAncestorsTable.self,
		CreateTriggerGuardTable.self,
	], in: database, clean: context == .live && isDebug)

	try database.setupTriggers([
		MakePagesViewWritable.self,
		MakeParagraphsViewWritable.self,

		TouchTimestamps.self,
		SyncAncestorsTable.self,
		SyncReferencesTable.self,
		UpdateParagraphOrder.self,
	])

	#if DEBUG
	try database.seed(SeedDatabase.self)
	#endif

	return database
}
