import Testing
import Foundation
import SQLiteData
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Models/Paragraph", .dependencies { try $0.bootstrapDatabase() })
	struct ParagraphTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.ParagraphTest {
	@Test("Paragraph.subtrees returns each selected root and descendant once")
	func subtreesReturnsRootsAndDescendants() throws {
		try database.write { db in
			let page = Block(title: "Root")
			let first = Block(string: "First", parentId: page.id)
			let child = Block(string: "Child", parentId: first.id)
			let grandchild = Block(string: "Grandchild", parentId: child.id)
			let second = Block(string: "Second", parentId: page.id, order: 1)
			let excluded = Block(string: "Excluded", parentId: second.id)
			let third = Block(string: "Third", parentId: page.id, order: 2)
			try Block.insert { [page, first, child, grandchild, second, excluded, third] }.execute(db)
			let result = try Paragraph.subtrees(rootedAt: [first.id, child.id, third.id]).order(by: \.id).select(\.id).fetchAll(db)
			expectNoDifference(result, [first.id, child.id, grandchild.id, third.id])
		}
	}
}

extension Tests.ParagraphTest {
	@Test("Inserting a Paragraph with an existing id fails instead of replacing it")
	func insertingDuplicateIDFails() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Root") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Original", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		do {
			try database.write { db in
				try Paragraph.insert {
					Paragraph(id: paragraph.id, string: "Replacement", parentId: page.id, pageId: page.id, order: 0)
				}.execute(db)
			}
			Issue.record("A duplicate paragraph ID must be rejected.")
		} catch let error as DatabaseError {
			expectNoDifference(error.extendedResultCode, .SQLITE_CONSTRAINT_PRIMARYKEY)
		}

		let stored = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})
		expectNoDifference(stored, paragraph)
	}
}

extension Tests.ParagraphTest {
	@Test("Selected paragraphs keep tree order without selecting their ancestors", arguments: [false, true], [false, true])
	func fetchInOrderWithUnselectedAncestors(withRedirect: Bool, wideRanks: Bool) throws {
		let expected = try database.write { db in
			let page = Block(id: UUID(1), title: "Page", createdAt: Date(timeIntervalSince1970: 100))
			let sameDate = Block(id: UUID(2), title: "Same date", createdAt: page.createdAt)
			let newer = Block(id: UUID(3), title: "Newer", createdAt: Date(timeIntervalSince1970: 200))
			let redirect = Block(id: UUID(4), title: "Page", mergedInto: page.id)
			let first = Block(id: UUID(100), string: "First", parentId: withRedirect ? redirect.id : page.id, order: wideRanks ? -9_000_000_000 : 0)
			let nested = Block(id: UUID(101), string: "Nested", parentId: first.id, order: Int.max)
			let leaf = Block(id: UUID(102), string: "Leaf", parentId: nested.id, order: Int.max)
			let unrelated = Block(id: UUID(150), string: "Unselected", parentId: page.id, order: 0)
			let second = Block(id: UUID(200), string: "Second", parentId: page.id, order: wideRanks ? 8_000_000_000 : 0)
			let secondChild = Block(id: UUID(201), string: "Second child", parentId: second.id, order: Int.min)
			let newerChild = Block(id: UUID(300), string: "Newer child", parentId: newer.id, order: 0)
			let sameDateChild = Block(id: UUID(400), string: "Same date child", parentId: sameDate.id, order: Int.min)
			let hidden = Block(id: UUID(500), string: "Deleted", parentId: page.id, deletedAt: Date(timeIntervalSince1970: 100))
			try Block.insert {
				[page, sameDate, newer] + (withRedirect ? [redirect] : [])
					+ [first, nested, leaf, unrelated, second, secondChild, newerChild, sameDateChild, hidden]
			}.execute(db)
			return [newerChild.id, leaf.id, second.id, secondChild.id, sameDateChild.id]
		}
		expectNoDifference(try Paragraph.fetchInOrder(Set(expected + [UUID(500), UUID(999)])).map(\.id), expected)
		expectNoDifference(try Paragraph.fetchInOrder([]), [])
	}
}
