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

	@Test("Moving a subtree replaces ancestors and page membership")
	func movingParagraphRebuildsSubtreeAncestors() throws {
		try database.write { db in
			let first = Block(title: "First page")
			let second = Block(title: "Second page")
			let oldParent = Block(string: "Old parent", parentId: first.id)
			let newParent = Block(string: "New parent", parentId: second.id)
			let child = Block(string: "Child", parentId: oldParent.id)
			let grandchild = Block(string: "Grandchild", parentId: child.id)
			try Block.insert { [first, second, oldParent, newParent, child, grandchild] }.execute(db)
			let storedGrandchild = try Block.find(grandchild.id).fetchOne(db)
			try Block.find(child.id).update { $0.parentId = #bind(newParent.id) }.execute(db)
			expectNoDifference(try Ancestor.where { $0.blockId.eq(child.id) }.order(by: \.depth).fetchAll(db), [
				Ancestor(blockId: child.id, ancestorId: newParent.id, depth: 1),
				Ancestor(blockId: child.id, ancestorId: second.id, depth: 2),
			])
			expectNoDifference(try Ancestor.where { $0.blockId.eq(grandchild.id) }.order(by: \.depth).fetchAll(db), [
				Ancestor(blockId: grandchild.id, ancestorId: child.id, depth: 1),
				Ancestor(blockId: grandchild.id, ancestorId: newParent.id, depth: 2),
				Ancestor(blockId: grandchild.id, ancestorId: second.id, depth: 3),
			])
			expectNoDifference(try Paragraph.find(child.id).fetchOne(db)?.pageId, second.id)
			expectNoDifference(try Paragraph.find(grandchild.id).fetchOne(db)?.pageId, second.id)
			expectNoDifference(try Block.find(grandchild.id).fetchOne(db), storedGrandchild)
		}
	}

	@Test("A cyclic parentId chain remains hidden", .timeLimit(.minutes(1)))
	func cyclicParentIdDoesNotHang() throws {
		@Dependency(\.uuid) var uuid
		let first = uuid()
		let second = uuid()

		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Ancestor Cycle Root") }.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert { Paragraph(id: first, string: "First", parentId: second, pageId: page.id, order: 0) }.execute(db)
			try Paragraph.insert { Paragraph(id: second, string: "Second", parentId: first, pageId: page.id, order: 0) }.execute(db)
		}

		expectNoDifference(try database.read { db in
			try Ancestor.where { $0.blockId.in([first, second]) }.order(by: \.blockId).fetchAll(db)
		}, [
			Ancestor(blockId: first, ancestorId: second, depth: 1),
			Ancestor(blockId: second, ancestorId: first, depth: 1),
		])

		#expect(try database.read { try Paragraph.withChildren(id: first).fetch($0) } == nil)
		#expect(try database.read { try BlockHierarchy.where(\.isVisible).fetchCount($0) } == 1)
	}
}
