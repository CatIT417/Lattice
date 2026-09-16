import Foundation
import SQLiteData

fileprivate nonisolated let logger = Logger(category: "Database")

@DatabaseFunction
var uuid: UUID {
	@Dependency(\.uuid) var uuid
	return uuid()
}

@DatabaseFunction
var now: Date {
	@Dependency(\.date.now) var now
	return now
}

func makeDatabase() throws -> any DatabaseWriter {
	@Dependency(\.context) var context

	let configuration = tap(Configuration()) { config in
		config.foreignKeysEnabled = true
		config.prepareDatabase { db in
			try db.attachMetadatabase()

			db.addFunctions([
				$now, $uuid, $searchContains, $searchDisplayTitle, $containsOutsideRefs, $searchDisplayString,
			])
			try db.setupViews([CreatePagesView.self, CreateParagraphsView.self, CreateBacklinksView.self])

			#if DEBUG
			db.trace(options: .profile) {
				guard !SyncEngine.isSynchronizing else { return }

				logger.debug("\($0.expandedDescription)")
			}
			#endif
		}
	}

	let database = try SQLiteData.defaultDatabase(configuration: configuration)
	logger.info("open '\(database.path)'")

	try database.write { db in
		try #sql("PRAGMA recursive_triggers = OFF").execute(db)
	}

	return database
}

func prepareDatabase(_ database: any DatabaseWriter) throws {
	var migrator = DatabaseMigrator()
	#if DEBUG
	if Bundle.main.isDev { migrator.eraseDatabaseOnSchemaChange = true }
	#endif

	try migrator.migrate([
		CreateBlocksTable.self,
		CreateReferencesTable.self,
		CreateAncestorsTable.self,
		CreateBlocksFTSTable.self,
		CreateCachedLinkMetadataTable.self,
		CreateLocalGraphIndexes.self,
	], in: database)

	try database.write { try RebuildSearchIndex.run(in: $0) }

	try database.setupTriggers([
		SafetyChecks.self,
		MakePagesViewWritable.self,
		MakeParagraphsViewWritable.self,

		SyncBlocksFTSTable.self,
		SyncAncestorsTable.self,
		SyncReferencesTable.self,
	])
}

func seedDatabase() {
	@Dependency(\.defaultDatabase) var database

	withErrorReporting {
		let hasSeeded = try database.read { try Select(Block.exists()).fetchOne($0) }
		guard !(hasSeeded ?? false) else { return }

		try database.seed(SeedDatabase.self)
	}
}
