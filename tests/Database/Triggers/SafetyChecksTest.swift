import Testing
import CustomDump
import SQLiteData
import Foundation
import GRDB
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SafetyChecks", .dependencies { try $0.bootstrapDatabase() })
	struct SafetyChecksTest {
		@Dependency(\.defaultDatabase) var database

		@Test("Title validation does not block sync", arguments: [false, true])
		func titleValidationDuringSync(update: Bool) throws {
			try database.write { db in
				let page = Block(title: "Original")
				if update { try Block.insert { page }.execute(db) }
				db.add(function: GRDB.DatabaseFunction(SyncEngine.$isSynchronizing.name, argumentCount: 0) { _ in true })
				defer { db.add(function: SyncEngine.$isSynchronizing) }

				if update {
					try Block.find(page.id).update { $0.title = #bind("Title [from sync]") }.execute(db)
				} else {
					try Block.insert { Block(id: page.id, title: "Title [from sync]") }.execute(db)
				}
				#expect(try Block.find(page.id).fetchOne(db)?.title == "Title [from sync]")
			}
		}

		@Test("A local move cannot create a cycle", arguments: [false, true])
		func rejectsCycles(selfParent: Bool) throws {
			try database.write { db in
				let page = Block(title: "Page")
				let parent = Block(string: "Parent", parentId: page.id)
				let child = Block(string: "Child", parentId: parent.id)
				try Block.insert { [page, parent, child] }.execute(db)
				let target = selfParent ? parent.id : child.id
				do {
					try Block.find(parent.id).update { $0.parentId = #bind(target) }.execute(db)
					Issue.record("The cyclic move must fail.")
				} catch let error as DatabaseError {
					expectNoDifference(error.extendedResultCode, .SQLITE_CONSTRAINT_TRIGGER)
					expectNoDifference(error.message, "A block cannot move under itself or a descendant.")
				}
				#expect(try Block.find(parent.id).fetchOne(db)?.parentId == page.id)
			}
		}
	}
}
