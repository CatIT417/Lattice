import Testing
import SQLiteData
import Foundation
import GRDB
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/TouchTimestamps", .dependencies { try $0.bootstrapDatabase() })
	struct TouchTimestampsTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.TouchTimestampsTest {
	@Test("Block.updatedAt is updated on record update")
	func updatedAtIsTouchedOnUpdate() throws {
		let block = try #require(database.write { db in
			try Block.insert { Block(title: "Test Page") }.returning(\.self).fetchOne(db)
		})

		#expect(block.createdAt == block.updatedAt)

		try database.write { db in
			try Block.find(block.id).update { $0.title = #bind("Updated Title") }.execute(db)
		}

		let updatedBlock = try database.read { db in
			try Block.find(block.id).fetchOne(db)
		}!

		#expect(block.updatedAt != updatedBlock.updatedAt)
	}

	@Test("A Page's updatedAt is updated when one of its child Blocks is updated",
		.dependencies { $0.date = .constant(Date(timeIntervalSince1970: 1_000)) })
	func pagesUpdatedAtIsTouchedOnChildUpdate() throws {
		let initialDate = Date(timeIntervalSince1970: 100)
		let (page, children) = try #require(database.write { db in
			let page = try Page.insert {
				Page(title: "Test Page", createdAt: initialDate, updatedAt: initialDate)
			}.returning(\.self).fetchOne(db)!
			let childBlocks = try Paragraph.insert {
				(0...3).map { i in
					Paragraph(string: "Child Block \(i)", parentId: page.id, pageId: page.id, order: i)
				}
			}.returning(\.self).fetchAll(db)

			return (page, childBlocks)
		})

		#expect(page.createdAt == page.updatedAt)

		let randomChild = try #require(children.randomElement())

		try database.write { db in
			try Block.find(randomChild.id).update { $0.string = #bind("Updated Child Block") }.execute(db)
		}

		let updatedPage = try #require(database.read { db in
			try Page.find(page.id).fetchOne(db)
		})

		#expect(updatedPage.updatedAt == Date(timeIntervalSince1970: 1_000))
	}
}

extension Tests.TouchTimestampsTest {
	@Suite(.dependencies { $0.date = .constant(Date(timeIntervalSince1970: 1_000)) })
	struct CachedPageTimestamps {
		@Dependency(\.defaultDatabase) var database
		@Test("Text edits use cached page membership without rebuilding hierarchy")
		func textEditUsesCache() throws {
			try database.write { db in
				let before = Date(timeIntervalSince1970: 100)
				let now = Date(timeIntervalSince1970: 1_000)
				let page = Block(title: "Page", updatedAt: before)
				let alias = Block(title: "Alias", updatedAt: before, mergedInto: page.id)
				let parent = Block(string: "Parent", parentId: alias.id, updatedAt: before)
				let child = Block(string: "Child", parentId: parent.id, updatedAt: before)
				try Block.insert { [page, alias, parent, child] }.execute(db)
				let rebuild = SyncAncestorsTable().$rebuildAncestorsForSubtree
				db.add(function: GRDB.DatabaseFunction(rebuild.name, argumentCount: 1) { _ in
					throw DatabaseError(message: "A text edit must not rebuild hierarchy.")
				})
				defer { db.add(function: rebuild) }
				try Block.find(child.id).update { $0.string = #bind("Edited") }.execute(db)
				#expect(try Block.find(child.id).fetchOne(db)?.updatedAt == now)
				#expect(try Block.find(page.id).fetchOne(db)?.updatedAt == now)
				expectNoDifference(try Block.find(parent.id).fetchOne(db), parent)
				expectNoDifference(try Block.find(alias.id).fetchOne(db), alias)
				try Block.find(child.id).update { $0.updatedAt = #bind(before) }.execute(db)
				#expect(try Block.find(child.id).fetchOne(db)?.updatedAt == before)
			}
		}

		@Test("Moves rebuild membership before local timestamps change", arguments: [false, true], [false, true])
		func moveTimestamps(remote: Bool, deletedDestination: Bool) throws {
			try database.write { db in
				let before = Date(timeIntervalSince1970: 100)
				let source = Block(title: "Source", updatedAt: before)
				let destination = Block(title: "Destination", updatedAt: before, deletedAt: deletedDestination ? before : nil)
				let alias = Block(title: "Alias", updatedAt: before, mergedInto: destination.id)
				let parent = Block(string: "Parent", parentId: alias.id, updatedAt: before)
				let child = Block(string: "Child", parentId: source.id, updatedAt: before)
				try Block.insert { [source, destination, alias, parent, child] }.execute(db)
				db.add(function: GRDB.DatabaseFunction(SyncEngine.$isSynchronizing.name, argumentCount: 0) { _ in remote })
				defer { db.add(function: SyncEngine.$isSynchronizing) }
				try Block.find(child.id).update {
					$0.parentId = #bind(parent.id)
					$0.string = #bind("Moved")
				}.execute(db)
				let expectedDate = remote ? before : Date(timeIntervalSince1970: 1_000)
				#expect(try Block.find(child.id).fetchOne(db)?.updatedAt == expectedDate)
				#expect(try Block.find(destination.id).fetchOne(db)?.updatedAt == expectedDate)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.pageId == destination.id)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.isVisible == !deletedDestination)
				expectNoDifference(try Block.find(source.id).fetchOne(db), source)
				expectNoDifference(try Block.find(parent.id).fetchOne(db), parent)
			}
		}

		@Test("A new redirect touches its final page after the hierarchy rebuild")
		func redirectTimestamps() throws {
			try database.write { db in
				let before = Date(timeIntervalSince1970: 100)
				let now = Date(timeIntervalSince1970: 1_000)
				let keeper = Block(title: "Keeper", updatedAt: before)
				let alias = Block(title: "Alias", updatedAt: before, mergedInto: keeper.id)
				let loser = Block(title: "Loser", updatedAt: before)
				let child = Block(string: "Child", parentId: loser.id, updatedAt: before)
				try Block.insert { [keeper, alias, loser, child] }.execute(db)
				try Block.find(loser.id).update { $0.mergedInto = #bind(alias.id) }.execute(db)
				#expect(try Block.find(loser.id).fetchOne(db)?.updatedAt == now)
				#expect(try Block.find(keeper.id).fetchOne(db)?.updatedAt == now)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.pageId == keeper.id)
				expectNoDifference(try Block.find(alias.id).fetchOne(db), alias)
				expectNoDifference(try Block.find(child.id).fetchOne(db), child)
			}
		}

		@Test("Deletion and restoration touch the containing page even while hidden")
		func deletionTimestamps() throws {
			try database.write { db in
				let before = Date(timeIntervalSince1970: 100)
				let now = Date(timeIntervalSince1970: 1_000)
				let page = Block(title: "Page", updatedAt: before)
				let child = Block(string: "Child", parentId: page.id, updatedAt: before)
				try Block.insert { [page, child] }.execute(db)
				try Paragraph.find(child.id).delete().execute(db)
				#expect(try Block.find(page.id).fetchOne(db)?.updatedAt == now)
				#expect(try Block.find(child.id).fetchOne(db)?.updatedAt == now)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.isVisible == false)
				let restoredAt = Date(timeIntervalSince1970: 2_000)
				try withDependencies { $0.date = .constant(restoredAt) } operation: {
					try Block.find(child.id).update { $0.deletedAt = #bind(Date?.none) }.execute(db)
				}
				#expect(try Block.find(page.id).fetchOne(db)?.updatedAt == restoredAt)
				#expect(try Block.find(child.id).fetchOne(db)?.updatedAt == restoredAt)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.isVisible == true)
			}
		}

		@Test("An unresolved chain touches only the edited block", arguments: [false, true])
		func unresolvedTimestamps(cycle: Bool) throws {
			try database.write { db in
				let before = Date(timeIntervalSince1970: 100)
				let page = Block(id: UUID(1), title: "Page", updatedAt: before)
				let child = Block(id: UUID(2), string: "Child", parentId: UUID(3), updatedAt: before)
				let parent = Block(id: UUID(3), string: "Parent", parentId: child.id, updatedAt: before)
				try Block.insert { [page, child] + (cycle ? [parent] : []) }.execute(db)
				try Block.find(child.id).update { $0.string = #bind("Edited") }.execute(db)
				#expect(try Block.find(child.id).fetchOne(db)?.updatedAt == Date(timeIntervalSince1970: 1_000))
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.pageId == nil)
				expectNoDifference(try Block.find(page.id).fetchOne(db), page)
				if cycle { expectNoDifference(try Block.find(parent.id).fetchOne(db), parent) }
			}
		}
	}
}
