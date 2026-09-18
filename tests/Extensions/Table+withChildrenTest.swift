import Testing
import Foundation
import SQLiteData
import CustomDump
import DependenciesTestSupport
import GRDB
import SQLite3

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/Table+withChildren", .dependencies { try $0.bootstrapDatabase() })
	struct TableWithChildrenTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.TableWithChildrenTest {
	@Test("Screen trees skip collapsed descendants and retain child checks")
	func visibleChildren() throws {
		try database.write { db in
			let page = Block(title: "Page")
			let closed = Block(string: "Closed", parentId: page.id, order: 0, isOpen: false)
			let hidden = Block(string: "Hidden", parentId: closed.id)
			let open = Block(string: "Open", parentId: page.id, order: 1)
			let nested = Block(string: "Nested", parentId: open.id, isOpen: false)
			let nestedHidden = Block(string: "Nested hidden", parentId: nested.id)
			let leaf = Block(string: "Leaf", parentId: page.id, order: 2, isOpen: false)
			try Block.insert { [page, closed, hidden, open, nested, nestedHidden, leaf] }.execute(db)

			let tree = try #require(Page.withVisibleChildren(id: page.id).fetch(db)?.tree)
			expectNoDifference(tree.children(of: page.id).map(\.id), [closed.id, open.id, leaf.id])
			expectNoDifference(tree.children(of: open.id).map(\.id), [nested.id])
			#expect(tree.get(byID: hidden.id) == nil)
			#expect(tree.get(byID: nestedHidden.id) == nil)
			#expect(tree.hasChildren(closed.id))
			#expect(tree.hasChildren(open.id))
			#expect(tree.hasChildren(nested.id))
			#expect(!tree.hasChildren(leaf.id))
			#expect(tree.subset(only: [closed.id]).hasChildren(closed.id))
			#expect(tree.nextBlockOnScreen(for: try #require(tree.get(byID: closed.id))) == open.id)
			#expect(tree.previousBlockOnScreen(for: try #require(tree.get(byID: leaf.id))) == nested.id)

			let fullTree = try #require(Page.withChildren(id: page.id).fetch(db)?.tree)
			#expect(fullTree.get(byID: hidden.id) != nil)
			#expect(fullTree.get(byID: nestedHidden.id) != nil)
			expectNoDifference(try Paragraph.descendantIDs(of: open.id, in: db), [nested.id, nestedHidden.id])
		}
	}

	@Test("A focused paragraph opens its root and ignores collapse above it")
	func focusedRoot() throws {
		try database.write { db in
			let page = Block(title: "Page")
			let parent = Block(string: "Parent", parentId: page.id, isOpen: false)
			let root = Block(string: "Root", parentId: parent.id, isOpen: false)
			let child = Block(string: "Child", parentId: root.id, isOpen: false)
			let hidden = Block(string: "Hidden", parentId: child.id)
			try Block.insert { [page, parent, root, child, hidden] }.execute(db)

			let result = try #require(try Paragraph.withVisibleChildren(id: root.id).fetch(db))
			expectNoDifference(result.tree.children(of: root.id).map(\.id), [child.id])
			#expect(result.tree.get(byID: hidden.id) == nil)
			#expect(result.tree.hasChildren(child.id))
			#expect(result.tree.previousBlockOnScreen(for: result.block) == nil)
			#expect(result.tree.nextBlockOnScreen(for: result.block) == child.id)
			#expect(result.tree.previousBlockOnScreen(for: try #require(result.tree.get(byID: child.id))) == root.id)
			#expect(result.tree.nextBlockOnScreen(for: try #require(result.tree.get(byID: child.id))) == nil)
		}
	}

	@Test("Screen trees resolve page redirects and stop at nested pages")
	func visiblePageRedirects() throws {
		try database.write { db in
			let page = Block(title: "Page")
			let alias = Block(title: "Alias", mergedInto: page.id)
			let olderAlias = Block(title: "Older alias", mergedInto: alias.id)
			let first = Block(string: "First", parentId: olderAlias.id, order: 0)
			let second = Block(string: "Second", parentId: page.id, order: 0)
			let inner = Block(title: "Inner page", parentId: first.id)
			let innerChild = Block(string: "Inner child", parentId: inner.id)
			try Block.insert { [page, alias, olderAlias, first, second, inner, innerChild] }.execute(db)

			let result = try #require(try Page.withVisibleChildren(id: olderAlias.id).fetch(db))
			#expect(result.block.id == page.id)
			expectNoDifference(result.tree.children(of: page.id).map(\.id), [first.id, second.id])
			#expect(result.tree.get(byID: first.id)?.parentId == page.id)
			#expect(!result.tree.hasChildren(first.id))
			#expect(result.tree.get(byID: innerChild.id) == nil)
			#expect(try Paragraph.withVisibleChildren(id: first.id).fetch(db)?.tree.get(byID: innerChild.id) == nil)
			#expect(try Page.withVisibleChildren(id: first.id).fetch(db) == nil)
		}
	}

	@Test("Screen child checks exclude deleted and unresolved structure")
	func visibleStructure() throws {
		try database.write { db in
			let page = Block(title: "Page")
			let parent = Block(string: "Parent", parentId: page.id, isOpen: false)
			let deleted = Block(string: "Deleted", parentId: parent.id)
			let child = Block(string: "Child", parentId: deleted.id)
			let missing = Block(string: "Missing", parentId: UUID(1000))
			let cycleA = Block(id: UUID(1001), string: "Cycle A", parentId: UUID(1002))
			let cycleB = Block(id: UUID(1002), string: "Cycle B", parentId: cycleA.id)
			try Block.insert { [page, parent, deleted, child, missing, cycleA, cycleB] }.execute(db)
			try Paragraph.find(deleted.id).delete().execute(db)

			let tree = try #require(Page.withVisibleChildren(id: page.id).fetch(db)?.tree)
			expectNoDifference(tree.children(of: page.id).map(\.id), [parent.id])
			#expect(!tree.hasChildren(parent.id))
			#expect(try Paragraph.descendantIDs(of: parent.id, in: db).isEmpty)
			#expect(try Paragraph.withVisibleChildren(id: missing.id).fetch(db) == nil)
			#expect(try Paragraph.withVisibleChildren(id: cycleA.id).fetch(db) == nil)
		}
	}

	@Test("Screen observations reload children after expansion and later edits")
	func visibleObservation() async throws {
		let page = Block(title: "Page")
		let parent = Block(string: "Parent", parentId: page.id, isOpen: false)
		let child = Block(string: "Before", parentId: parent.id)
		try await database.write { db in
			try Block.insert { [page, parent, child] }.execute(db)
		}
		var values = ValueObservation.tracking { db in
			try Page.withVisibleChildren(id: page.id).fetch(db)?.tree.get(byID: child.id)?.string ?? "Hidden"
		}.values(in: database).makeAsyncIterator()
		#expect(try await values.next() == "Hidden")
		try await database.write { db in
			try Block.find(parent.id).update { $0.isOpen = true }.execute(db)
		}
		#expect(try await values.next() == "Before")
		try await database.write { db in
			try Block.find(child.id).update { $0.string = #bind("After") }.execute(db)
		}
		#expect(try await values.next() == "After")
		try await database.write { db in
			try Block.find(parent.id).update { $0.isOpen = false }.execute(db)
		}
		#expect(try await values.next() == "Hidden")
	}

	@Test("Collapsed query work does not grow with hidden descendants")
	func visibleQueryCost() throws {
		let database = try makeDatabase()
		try database.write { db in
			try CreateBlocksTable.up(db)
			try CreateAncestorsTable.up(db)
			try CreateLocalGraphIndexes.up(db)
			let page = Block(title: "Page")
			let parent = Block(string: "Parent", parentId: page.id, isOpen: false)
			try Block.insert { [page, parent] }.execute(db)
			try BlockHierarchy.insert {
				[page, parent].map { BlockHierarchy(blockId: $0.id, pageId: page.id, isVisible: true) }
			}.execute(db)
			let query = WithChildrenRequest<Page>.visibleParagraphs(rootID: page.id)
			let (sql, _) = query.query.prepare { _ in "?" }
			let statement = try db.cachedStatement(sql: sql)
			func steps() throws -> Int32 {
				sqlite3_stmt_status(statement.sqliteStatement, SQLITE_STMTSTATUS_VM_STEP, 1)
				let rows = try query.fetchAll(db)
				#expect(rows.count == 1)
				return sqlite3_stmt_status(statement.sqliteStatement, SQLITE_STMTSTATUS_VM_STEP, 0)
			}
			let small = try steps()
			let hidden = (0..<1000).map { _ in Block(string: "Hidden", parentId: parent.id) }
			try Block.insert { hidden }.execute(db)
			try BlockHierarchy.insert {
				hidden.map { BlockHierarchy(blockId: $0.id, pageId: page.id, isVisible: true) }
			}.execute(db)
			let large = try steps()
			#expect(small > 0)
			#expect(large < small * 2)
			#expect(try Page.withVisibleChildren(id: page.id).fetch(db)?.tree.hasChildren(parent.id) == true)
		}
	}

	@Test("A paragraph ID is not a page ID")
	func pageRejectsParagraphID() throws {
		try database.write { db in
			let page = Block(title: "Page")
			let paragraph = Block(string: "Paragraph", parentId: page.id)
			try Block.insert { [page, paragraph] }.execute(db)
			#expect(try Page.withChildren(id: paragraph.id).fetch(db) == nil)
			#expect(try Page.withChildren(id: page.id).fetch(db)?.block.id == page.id)
		}
	}

	@Test("A page root stops ancestry even when it has a stored parent")
	func ancestryStopsAtPage() throws {
		try database.write { db in
			let outer = Block(title: "Outer page")
			let parent = Block(string: "Parent", parentId: outer.id)
			let inner = Block(title: "Inner page", parentId: parent.id)
			let child = Block(string: "Child", parentId: inner.id)
			try Block.insert { [outer, parent, inner, child] }.execute(db)
			#expect(try Ancestor.where { $0.blockId.eq(inner.id) }.fetchCount(db) == 0)
			expectNoDifference(try Ancestor.where { $0.blockId.eq(child.id) }.select(\.ancestorId).fetchAll(db), [inner.id])
			#expect(try Paragraph.withChildren(id: parent.id).fetch(db)?.tree.get(byID: child.id) == nil)
			#expect(try Page.withChildren(id: inner.id).fetch(db)?.tree.get(byID: child.id)?.id == child.id)
			expectNoDifference(try Breadcrumb.forBlock(id: child.id).fetchAll(db).map(\.id), [inner.id])
		}
	}

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
			try Page.withChildren(id: page.id).fetch(db)
		})

		expectNoDifference(page.id, result.block.id)
		expectNoDifference(page.canonicalTitle, result.block.canonicalTitle)
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
			try Paragraph.withChildren(id: root.id).fetch(db)
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
			try Page.withChildren(id: page.id).fetch(db)
		})

		expectNoDifference([], result.tree.children(of: page.id).map(\.id))
	}
}
