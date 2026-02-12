import SQLiteData
import Foundation
import Dependencies

extension DependencyValues {
	mutating func bootstrapDatabase() throws {
		defaultDatabase = try makeDatabase()
		try prepareDatabase(defaultDatabase)

		defaultSyncEngine = try SyncEngine(for: defaultDatabase, tables: Block.self)
	}
}
