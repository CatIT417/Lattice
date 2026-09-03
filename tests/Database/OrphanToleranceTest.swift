import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/OrphanTolerance", .dependencies { try $0.bootstrapDatabase() })
	struct OrphanToleranceTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.OrphanToleranceTest {
	@Test("A paragraph whose parent has not arrived is stored, hidden, and rendered once the parent arrives")
	func paragraphWithMissingParentRendersOnceParentArrives() throws {
		@Dependency(\.uuid) var uuid
		let parentID = uuid()

		let (page, child) = try database.write { db in
			let page = try #require(try Page.insert { Page(title: "Orphan Root") }.returning(\.self).fetchOne(db))
			let child = try #require(try Paragraph.insert {
				Paragraph(string: "Child", parentId: parentID, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			return (page, child)
		}

		let before = try #require(database.read { db in try Page.withChildren(id: page.id).fetch(db) })
		expectNoDifference(before.tree.children(of: page.id).map(\.id), [])

		let parent = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(id: parentID, string: "Parent", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let after = try #require(database.read { db in try Page.withChildren(id: page.id).fetch(db) })
		expectNoDifference(after.tree.children(of: page.id).map(\.id), [parent.id])
		expectNoDifference(after.tree.children(of: parent.id).map(\.id), [child.id])

		let childAncestors = try database.read { db in
			try Ancestor.where { $0.blockId.eq(child.id) }.order { $0.depth.asc() }.fetchAll(db)
		}
		expectNoDifference(childAncestors, [
			Ancestor(blockId: child.id, ancestorId: parent.id, depth: 1),
			Ancestor(blockId: child.id, ancestorId: page.id, depth: 2),
		])
	}
}
