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
	@Test("Paragraph.subtrees returns the given paragraphs and their descendants, nothing else")
	func subtreesReturnsRootsAndDescendants() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Root") }.returning(\.self).fetchOne(db)
		})

		let first = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "First", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let firstChild = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "First Child", parentId: first.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let grandchild = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Grandchild", parentId: firstChild.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let second = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Second", parentId: page.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Second Child", parentId: second.id, pageId: page.id, order: 0)
			}.execute(db)
		}

		let third = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Third", parentId: page.id, pageId: page.id, order: 2)
			}.returning(\.self).fetchOne(db)
		})

		let result = try database.read { db in
			try Paragraph.subtrees(rootedAt: [first.id, third.id]).fetchAll(db)
		}

		expectNoDifference(Set([first.id, firstChild.id, grandchild.id, third.id]), Set(result.map(\.id)))
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

		#expect(throws: (any Error).self) {
			try database.write { db in
				try Paragraph.insert {
					Paragraph(id: paragraph.id, string: "Replacement", parentId: page.id, pageId: page.id, order: 0)
				}.execute(db)
			}
		}

		let stored = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})
		expectNoDifference(stored.string, "Original")
	}
}

extension Tests.ParagraphTest {
	@Test("Selected paragraphs keep tree order without selecting their ancestors", arguments: [false, true])
	func fetchInOrderWithUnselectedAncestors(withRedirect: Bool) throws {
		let expected = try database.write { db in
			let page = Block(id: UUID(1), title: "Page", createdAt: Date(timeIntervalSince1970: 100))
			let sameDate = Block(id: UUID(2), title: "Same date", createdAt: page.createdAt)
			let newer = Block(id: UUID(3), title: "Newer", createdAt: Date(timeIntervalSince1970: 200))
			let redirect = Block(id: UUID(4), title: "Page", mergedInto: page.id)
			let first = Block(id: UUID(100), string: "First", parentId: withRedirect ? redirect.id : page.id, order: 0)
			let nested = Block(id: UUID(101), string: "Nested", parentId: first.id, order: Int.max)
			let leaf = Block(id: UUID(102), string: "Leaf", parentId: nested.id, order: Int.max)
			let unrelated = Block(id: UUID(150), string: "Unselected", parentId: page.id, order: 0)
			let second = Block(id: UUID(200), string: "Second", parentId: page.id, order: 0)
			let secondChild = Block(id: UUID(201), string: "Second child", parentId: second.id, order: Int.min)
			let newerChild = Block(id: UUID(300), string: "Newer child", parentId: newer.id, order: 0)
			let sameDateChild = Block(id: UUID(400), string: "Same date child", parentId: sameDate.id, order: Int.min)
			let hidden = Block(id: UUID(500), string: "Deleted", parentId: page.id, deletedAt: Date())
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
