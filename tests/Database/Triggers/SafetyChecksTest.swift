import Testing
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
				#expect(throws: DatabaseError.self) {
					try Block.find(parent.id).update { $0.parentId = #bind(target) }.execute(db)
				}
				#expect(try Block.find(parent.id).fetchOne(db)?.parentId == page.id)
			}
		}

		@Test("Changing only parentId moves a whole subtree to its new page")
		func crossPageMove() throws {
			try database.write { db in
				let first = Block(title: "First")
				let second = Block(title: "Second")
				let parent = Block(string: "Parent", parentId: first.id)
				let child = Block(string: "Child", parentId: parent.id)
				try Block.insert { [first, second, parent, child] }.execute(db)
				let storedChild = try Block.find(child.id).fetchOne(db)
				try Block.find(parent.id).update { $0.parentId = #bind(second.id) }.execute(db)
				#expect(try Paragraph.find(parent.id).fetchOne(db)?.pageId == second.id)
				#expect(try Paragraph.find(child.id).fetchOne(db)?.pageId == second.id)
				#expect(try Block.find(child.id).fetchOne(db) == storedChild)
			}
		}
	}
}
