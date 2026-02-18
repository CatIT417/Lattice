import Testing
import SQLiteData
import InlineSnapshotTesting

@testable import LatticeDev

extension Tests {
	@Suite("Support/MarkdownExporter")
	struct MarkdownExporterTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.MarkdownExporterTest {
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

	@Test("exports nested children with tab indentation")
	func pageExportNested() throws {
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

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Grandchild", parentId: child.id, pageId: page.id, order: 0)
			}.execute(db)
		}

		let result = try MarkdownExporter.exportPage(id: page.id)

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			# Nested

			- Parent
				- Child
					- Grandchild
			"""
		}
	}

	@Test("exports numbered list items")
	func numberedListItems() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Numbers") }.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "First", parentId: page.id, pageId: page.id, order: 0, viewType: .numbered)
			}.execute(db)

			try Paragraph.insert {
				Paragraph(string: "Second", parentId: page.id, pageId: page.id, order: 1, viewType: .numbered)
			}.execute(db)
		}

		let result = try MarkdownExporter.exportPage(id: page.id)

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			# Numbers

			1. First
			1. Second
			"""
		}
	}

	@Test("exports heading paragraphs with bullet prefix")
	func headingParagraphs() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Headings") }.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Big heading", parentId: page.id, pageId: page.id, order: 0, heading: .h1)
			}.execute(db)

			try Paragraph.insert {
				Paragraph(string: "Medium heading", parentId: page.id, pageId: page.id, order: 1, heading: .h2)
			}.execute(db)

			try Paragraph.insert {
				Paragraph(string: "Small heading", parentId: page.id, pageId: page.id, order: 2, heading: .h3)
			}.execute(db)
		}

		let result = try MarkdownExporter.exportPage(id: page.id)

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			# Headings

			- # Big heading
			- ## Medium heading
			- ### Small heading
			"""
		}
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

	@Test("exports a paragraph with its descendants")
	func paragraphExport() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "Root") }.returning(\.self).fetchOne(db)
		})

		let root = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Root paragraph", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Child A", parentId: root.id, pageId: page.id, order: 0)
			}.execute(db)

			try Paragraph.insert {
				Paragraph(string: "Child B", parentId: root.id, pageId: page.id, order: 1)
			}.execute(db)
		}

		let result = try MarkdownExporter.exportParagraph(id: root.id)

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			- Root paragraph
				- Child A
				- Child B
			"""
		}
	}

	@Test("exports empty selection as empty string")
	func emptySelection() throws {
		let result = try MarkdownExporter.exportSelection([])

		assertInlineSnapshot(of: result, as: .lines) {
			""
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

	@Test("exports seeded page correctly")
	func seedDatabaseExport() throws {
		try database.seed(SeedDatabase.self)

		let page = try #require(database.read { db in
			try Page.where { $0.dailyNoteDate.is(nil) }.fetchOne(db)
		})

		let result = try MarkdownExporter.exportPage(id: page.id)

		assertInlineSnapshot(of: result, as: .lines) {
			"""
			# Lattice Quick Start

			- What is Lattice?
				- Lattice is a tool for thinking, heavily inspired by [[Roam Research]]
				- Unlike other "Roam Clones", every bullet is a block
					- It can be linked to, referenced, embed, etc.
					- This is my favourite part of Roam, and I can't believe everyone else just left it for Markdown
				- You can install Lattice on your iPhone, iPad, or Mac
					- all your data seamlessly syncs using iCloud
					- at the same time, the app works fully offline, so you can jot down ideas anywhere, anytime (and they'll sync back once you're back online)
				- Lattice is a native app, built with Swift, using [[UITextView]]/[[NSTextView]]
					- It's also open-source, and you can check out the code on [GitHub](https://github.com/m1guelpf/Lattice)
			- How Lattice works
				- Like I mentioned before, every bullet is a block
					- You can infinitely nest blocks inside other blocks
					- Click the bullet to the left of a block to navigate into it
					- You can also embed blocks inside other blocks to reference them (but we'll get to that later)
				- Blocks can include references to [[Pages]] using `[[this syntax]]`.
					- Pages track all references to them across your entire database
						- This makes it easy to build a web of interconnected ideas, track common themes, etc.
					- You can also style them as #tags to make their "tagging" nature more obvious
			- Mastering Lattice
				- Press `Return` to create a new block after the current one
				- Press `Delete` at the start of a block to join it with the previous one
				- todo: add the rest of the shortcuts here
			- More soon!
				- Lattice is under active development, so you can expect many more features soon, as it slowly morphs into a proper "second brain"
				- If this excites you, hit me up! [@m1guelpf](https://twitter.com/m1guelpf) on Twitter.
			"""
		}
	}
}
