import SQLiteData
import Foundation
import Dependencies

extension DependencyValues {
	mutating func bootstrapDatabase() throws {
		defaultDatabase = try makeDatabase()
		try prepareDatabase(defaultDatabase)

		if context == .live, !Bundle.main.isDev {
			defaultSyncEngine = try SyncEngine(for: defaultDatabase, tables: Block.self)
		}
	}
}
