import SQLiteData
import Dependencies

extension DependencyValues {
	mutating func bootstrapDatabase() throws {
		defaultDatabase = try appDatabase()

		#if !DEBUG
		@Dependency(\.context) var context
		if context == .live {
			defaultSyncEngine = try SyncEngine(for: defaultDatabase, tables: Block.self)
		}
		#endif
	}
}
