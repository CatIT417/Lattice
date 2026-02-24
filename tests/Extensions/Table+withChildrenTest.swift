import Testing
import SQLiteData
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/Table+withChildren", .dependencies { try $0.bootstrapDatabase() })
	struct TableWithChildrenTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.TableWithChildrenTest {
	@Test("Page.withChildren returns the full descendant tree")
	func pageWithChildrenReturnsTree() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Root") }.returning(\.self).fetchOne(db)
		})

		let first = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "First", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let second = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Second", parentId: page.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		let firstChild = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "First Child", parentId: first.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let secondChild = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Second Child", parentId: first.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		let grandchild = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Grandchild", parentId: firstChild.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let secondBranchChild = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Second Branch Child", parentId: second.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let result = try #require(database.read { db in
			try Page.withChildren(id: page.id).fetchOne(db)
		})

		expectNoDifference(page.id, result.block.id)
		expectNoDifference(page.title, result.block.title)
		expectNoDifference([first.id, second.id], result.tree.children(of: page.id).map(\.id))
		expectNoDifference([firstChild.id, secondChild.id], result.tree.children(of: first.id).map(\.id))
		expectNoDifference([grandchild.id], result.tree.children(of: firstChild.id).map(\.id))
		expectNoDifference([secondBranchChild.id], result.tree.children(of: second.id).map(\.id))
		expectNoDifference([], result.tree.children(of: secondChild.id).map(\.id))
	}

	@Test("Paragraph.withChildren returns only its descendants")
	func paragraphWithChildrenReturnsSubtree() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Root") }.returning(\.self).fetchOne(db)
		})

		let root = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Root", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let child = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Child", parentId: root.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let sibling = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Sibling", parentId: page.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		let grandchild = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Grandchild", parentId: child.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let result = try #require(database.read { db in
			try Paragraph.withChildren(id: root.id).fetchOne(db)
		})

		expectNoDifference(root.id, result.block.id)
		expectNoDifference([child.id], result.tree.children(of: root.id).map(\.id))
		expectNoDifference([grandchild.id], result.tree.children(of: child.id).map(\.id))
		expectNoDifference([], result.tree.children(of: page.id).map(\.id))
		expectNoDifference([], result.tree.children(of: sibling.id).map(\.id))
	}

	@Test("withChildren returns an empty tree when there are no descendants")
	func withChildrenHandlesEmptyContent() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Empty") }.returning(\.self).fetchOne(db)
		})

		let result = try #require(database.read { db in
			try Page.withChildren(id: page.id).fetchOne(db)
		})

		expectNoDifference([], result.tree.children(of: page.id).map(\.id))
	}
}
