import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SyncAncestorsTable", .dependencies { try $0.bootstrapDatabase() })
	struct SyncAncestorsTableTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.SyncAncestorsTableTest {
	@Test("Inserting a Paragraph propagates parent ancestors")
	func insertingParagraphPropagatesParentAncestors() throws {
		let (page, parent, child) = try database.write { db in
			let page = try #require(try Page.insert { Page(title: "Ancestor Root") }.returning(\.self).fetchOne(db))

			let parent = try #require(try Paragraph.insert {
				Paragraph(string: "Parent", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			let child = try #require(try Paragraph.insert {
				Paragraph(string: "Child", parentId: parent.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			return (page, parent, child)
		}

		let parentAncestors = try database.read { db in
			try Ancestor.where { $0.blockId.eq(parent.id) }
				.order { $0.depth.asc() }
				.fetchAll(db)
		}

		expectNoDifference(parentAncestors, [
			Ancestor(blockId: parent.id, ancestorId: page.id, depth: 1),
		])

		let childAncestors = try database.read { db in
			try Ancestor.where { $0.blockId.eq(child.id) }
				.order { $0.depth.asc() }
				.fetchAll(db)
		}

		expectNoDifference(childAncestors, [
			Ancestor(blockId: child.id, ancestorId: parent.id, depth: 1),
			Ancestor(blockId: child.id, ancestorId: page.id, depth: 2),
		])
	}

	@Test("Moving a Paragraph rebuilds ancestor rows for its subtree")
	func movingParagraphRebuildsSubtreeAncestors() throws {
		let (page, secondRoot, child, grandchild) = try database.write { db in
			let page = try #require(try Page.insert { Page(title: "Ancestor Move Root") }.returning(\.self).fetchOne(db))

			let firstRoot = try #require(try Paragraph.insert {
				Paragraph(string: "First Root", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			let secondRoot = try #require(try Paragraph.insert {
				Paragraph(string: "Second Root", parentId: page.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db))

			let child = try #require(try Paragraph.insert {
				Paragraph(string: "Child", parentId: firstRoot.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			let grandchild = try #require(try Paragraph.insert {
				Paragraph(string: "Grandchild", parentId: child.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			return (page, secondRoot, child, grandchild)
		}

		try database.write { db in
			try Block.find(child.id).update {
				$0.parentId = #bind(secondRoot.id)
			}.execute(db)
		}

		let childAncestors = try database.read { db in
			try Ancestor.where { $0.blockId.eq(child.id) }
				.order { $0.depth.asc() }
				.fetchAll(db)
		}

		expectNoDifference(childAncestors, [
			Ancestor(blockId: child.id, ancestorId: secondRoot.id, depth: 1),
			Ancestor(blockId: child.id, ancestorId: page.id, depth: 2),
		])

		let grandchildAncestors = try database.read { db in
			try Ancestor.where { $0.blockId.eq(grandchild.id) }
				.order { $0.depth.asc() }
				.fetchAll(db)
		}

		expectNoDifference(grandchildAncestors, [
			Ancestor(blockId: grandchild.id, ancestorId: child.id, depth: 1),
			Ancestor(blockId: grandchild.id, ancestorId: secondRoot.id, depth: 2),
			Ancestor(blockId: grandchild.id, ancestorId: page.id, depth: 3),
		])
	}

	@Test("A cyclic parentId chain does not hang the ancestor rebuild")
	func cyclicParentIdDoesNotHang() throws {
		@Dependency(\.uuid) var uuid
		let first = uuid()
		let second = uuid()

		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Ancestor Cycle Root") }.returning(\.self).fetchOne(db)
		})

		// Nothing stops two concurrent moves from merging into a cycle. Both inserts must return; the rows are unspecified.
		try database.write { db in
			try Paragraph.insert { Paragraph(id: first, string: "First", parentId: second, pageId: page.id, order: 0) }.execute(db)
			try Paragraph.insert { Paragraph(id: second, string: "Second", parentId: first, pageId: page.id, order: 0) }.execute(db)
		}

		let ancestorRows = try database.read { db in
			try Ancestor.where { $0.blockId.in([first, second]) }.fetchCount(db)
		}
		#expect(ancestorRows > 0)

		// Neither block may be its own ancestor, or a tree built from these rows would loop when rendered.
		let selfRows = try database.read { db in
			try Ancestor.where { $0.blockId.eq($0.ancestorId) }.fetchCount(db)
		}
		expectNoDifference(selfRows, 0)

		let tree = try #require(database.read { db in try Paragraph.withChildren(id: first).fetch(db) }).tree
		expectNoDifference(tree.children(of: first).map(\.id), [second])
		expectNoDifference(tree.children(of: second).map(\.id), [])
	}
}
