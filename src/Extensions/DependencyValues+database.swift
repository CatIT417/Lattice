import SQLiteData
import Foundation
import Dependencies

extension DependencyValues {
	mutating func bootstrapDatabase() throws {
		defaultDatabase = try appDatabase()

		@Dependency(\.context) var context
		if context == .live, !Bundle.main.isDev {
			defaultSyncEngine = try SyncEngine(for: defaultDatabase, tables: Block.self)
		}
	}
}
