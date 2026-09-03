import Testing
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
