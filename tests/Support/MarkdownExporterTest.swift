import Testing
import CustomDump
import SQLiteData
import InlineSnapshotTesting
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Support/MarkdownExporter", .dependencies { try $0.bootstrapDatabase() })
	struct MarkdownExporterTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.MarkdownExporterTest {
	@Test("Exports retain descendants of collapsed paragraphs")
	func collapsedDescendants() throws {
		let page = Block(title: "Page")
		let parent = Block(string: "Parent", parentId: page.id, isOpen: false)
		let child = Block(string: "Child", parentId: parent.id, isOpen: false)
		let grandchild = Block(string: "Grandchild", parentId: child.id)
		let sibling = Block(string: "Sibling", parentId: parent.id, order: 1)
		try database.write { db in
			try Block.insert { [page, parent, child, grandchild, sibling] }.execute(db)
		}

		#expect(try MarkdownExporter.exportPage(id: page.id) == "# Page\n\n- Parent\n\t- Child\n\t\t- Grandchild\n\t- Sibling")
		#expect(try MarkdownExporter.exportParagraph(id: parent.id) == "- Parent\n\t- Child\n\t\t- Grandchild\n\t- Sibling")
	}

	@Test("exports a page with H1 title and bullet children")
	func pageExportBasic() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "My Page") }.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "First", parentId: page.id, pageId: page.id, order: 0)
			}.execute(db)

			try Paragraph.insert {
				Paragraph(string: "Second", parentId: page.id, pageId: page.id, order: 1)
			}.execute(db)
		}

		let result = try MarkdownExporter.exportPage(id: page.id)

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			# My Page

			- First
			- Second
			"""
		}
	}

	@Test("Export preserves the paragraph style and heading", arguments: [
		(Block.ViewType.numbered, nil as Block.HeadingLevel?, "1. Text"),
		(.document, nil, "Text"),
		(.bullet, .h1, "- # Text"),
		(.bullet, .h2, "- ## Text"),
		(.bullet, .h3, "- ### Text"),
	])
	func paragraphStyle(viewType: Block.ViewType, heading: Block.HeadingLevel?, expected: String) throws {
		let page = Page(title: "Style")
		let paragraph = Paragraph(string: "Text", parentId: page.id, pageId: page.id, order: 0, heading: heading, viewType: viewType)
		try database.write { db in
			try Page.insert { page }.execute(db)
			try Paragraph.insert { paragraph }.execute(db)
		}
		expectNoDifference(try MarkdownExporter.exportPage(id: page.id), "# Style\n\n\(expected)")
	}

	@Test("exports selection with only listed IDs, no children")
	func selectionExport() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Selection") }.returning(\.self).fetchOne(db)
		})

		let first = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Selected A", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Child of A (should not appear)", parentId: first.id, pageId: page.id, order: 0)
			}.execute(db)
		}

		let second = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Selected B", parentId: page.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		expectNoDifference(try MarkdownExporter.exportSelection([]), "")
		let result = try MarkdownExporter.exportSelection([first.id, second.id])

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			- Selected A
			- Selected B
			"""
		}
	}

	@Test("exports nested selection")
	func exportNestedSelection() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Nested") }.returning(\.self).fetchOne(db)
		})

		let parent = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Parent", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let child = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Child", parentId: parent.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let grandchild = try #require(try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Grandchild", parentId: child.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let result = try MarkdownExporter.exportSelection([parent.id, child.id, grandchild.id])

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			- Parent
				- Child
					- Grandchild
			"""
		}
	}

	@Test("exports empty page with just the title")
	func emptyPage() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Empty") }.returning(\.self).fetchOne(db)
		})

		let result = try MarkdownExporter.exportPage(id: page.id)

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			# Empty

			"""
		}
	}

	@Test("exports selection in document order across different parents")
	func selectionDocumentOrder() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Order Test") }.returning(\.self).fetchOne(db)
		})

		let a = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "A", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let b = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "B", parentId: a.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let c = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "C", parentId: a.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		let d = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "D", parentId: page.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		// B(order 0) and D(order 1) would sort before C(order 1) with naive .order sort
		// Document order should be: B, C, D
		let result = try MarkdownExporter.exportSelection([b.id, c.id, d.id])

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			- B
			- C
			- D
			"""
		}
	}
}
