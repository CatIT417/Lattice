import Foundation
import SQLiteData
import Dependencies

extension DependencyValues {
	mutating func bootstrapDatabase() throws {
		defaultDatabase = try makeDatabase()
		try prepareDatabase(defaultDatabase)

		defaultSyncEngine = try SyncEngine(for: defaultDatabase, tables: Block.self)

		_ = try defaultDatabase.write { try MergeDuplicatePages.run(in: $0) }

		if context == .live, Bundle.main.isDev {
			Task { seedDatabase() }
		}
	}
}
