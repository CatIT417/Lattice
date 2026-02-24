import Testing
import SQLiteData
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Models/TriggerGuard", .dependencies { try $0.bootstrapDatabase() })
	struct TriggerGuardTest {
		@Dependency(\.defaultDatabase) var database
	}
}

// We intentionally use the write connection for reads here, because
// TriggerGuard is available only within write transactions.
extension Tests.TriggerGuardTest {
	@Test("Trigger guard is seeded and starts inactive")
	func startsInactive() throws {
		let triggerGuard = try #require(database.write { db in
			try TriggerGuard.find(0).fetchOne(db)
		})

		let isActive = try #require(database.write { db in
			try TriggerGuard.isActive.fetchOne(db)
		} as Bool?)

		expectNoDifference(false, isActive)
		expectNoDifference(0, triggerGuard.depth)
	}

	@Test("Increment and decrement update depth and activity")
	func incrementAndDecrement() throws {
		try database.write { db in
			try TriggerGuard.increment().execute(db)
			try TriggerGuard.increment().execute(db)
		}

		let depthAfterIncrement = try #require(database.write { db in
			try TriggerGuard.find(0).fetchOne(db)
		})

		let isActiveAfterIncrement = try #require(database.write { db in
			try TriggerGuard.isActive.fetchOne(db)
		} as Bool?)

		expectNoDifference(2, depthAfterIncrement.depth)
		expectNoDifference(true, isActiveAfterIncrement)

		try database.write { db in
			try TriggerGuard.decrement().execute(db)
			try TriggerGuard.decrement().execute(db)
		}

		let depthAfterDecrement = try #require(database.write { db in
			try TriggerGuard.find(0).fetchOne(db)
		})

		let isActiveAfterDecrement = try #require(database.write { db in
			try TriggerGuard.isActive.fetchOne(db)
		} as Bool?)

		expectNoDifference(0, depthAfterDecrement.depth)
		expectNoDifference(false, isActiveAfterDecrement)
	}
}
