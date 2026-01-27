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

			if context == .live, !Bundle.main.isDev {
				try db.attachMetadatabase()
			}

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
	if Bundle.main.isDev { migrator.eraseDatabaseOnSchemaChange = true }
	#endif

	try database.write { db in
		try #sql("PRAGMA recursive_triggers = OFF").execute(db)
	}

	try migrator.migrate([
		CreateBlocksTable.self,
		CreateReferencesTable.self,
		CreateAncestorsTable.self,
		CreateTriggerGuardTable.self,
	], in: database, clean: context == .live && isDebug && Bundle.main.isDev)

	try database.setupTriggers([
		MakePagesViewWritable.self,
		MakeParagraphsViewWritable.self,

		TouchTimestamps.self,
		SyncAncestorsTable.self,
		AvoidDuplicatePages.self,
		SyncReferencesTable.self,
		UpdateParagraphOrder.self,
	])

	#if DEBUG
	if Bundle.main.isDev {
		try database.seed(SeedDatabase.self)
	}
	#endif

	return database
}
