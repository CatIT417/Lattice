import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SyncReferencesTable", .dependency(\.date, .constant(.distantPast)))
	struct SyncReferencesTableTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.SyncReferencesTableTest {
	@Test("Inserting a Paragraph with references creates pages and references")
	func insertingParagraphCreatesReferences() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw [[Megalopolis]] again #onPlex", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let pageLinkPage = try #require(database.read { db in
			try Page.where { $0.title == "Megalopolis" }.fetchOne(db)
		})

		let tagPage = try #require(database.read { db in
			try Page.where { $0.title == "onPlex" }.fetchOne(db)
		})

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId == paragraph.id }.fetchAll(db)
		}

		expectNoDifference(references, [
			Reference(id: UUID(4), sourceBlockId: paragraph.id, targetBlockId: pageLinkPage.id, kind: .pageLink),
			Reference(id: UUID(5), sourceBlockId: paragraph.id, targetBlockId: tagPage.id, kind: .tag),
		])
	}

	@Test("Updating a Paragraph string replaces references")
	func updatingParagraphStringReplacesReferences() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw [[Megalopolis]] again #onPlex", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(paragraph.id).update {
				$0.string = "Saw [[Tenet]] once more"
			}.execute(db)
		}

		let newPage = try #require(database.read { db in
			try Page.where { $0.title == "Tenet" }.fetchOne(db)
		})

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId == paragraph.id }.fetchAll(db)
		}

		expectNoDifference(references, [
			Reference(id: UUID(7), sourceBlockId: paragraph.id, targetBlockId: newPage.id, kind: .pageLink),
		])
	}

	@Test("Renaming a Page updates wiki link references")
	func renamingPageUpdatesWikiLinks() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let referencedPage = try #require(database.write { db in
			try Page.insert { Page(title: "Meglopolis") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw [[Meglopolis]]", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(referencedPage.id).update { $0.title = "Megalopolis" }.execute(db)
		}

		let updatedParagraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(updatedParagraph.string, "Saw [[Megalopolis]]")

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId == paragraph.id }.fetchAll(db)
		}

		expectNoDifference(references, [
			Reference(id: UUID(4), sourceBlockId: paragraph.id, targetBlockId: referencedPage.id, kind: .pageLink),
		])
	}

	@Test("Renaming a tag page updates tag syntax")
	func renamingTagPageUpdatesTagSyntax() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favorite Movies") }.returning(\.self).fetchOne(db)
		})

		let tagPage = try #require(database.write { db in
			try Page.insert { Page(title: "cinema") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw Megalopolis #cinema", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(tagPage.id).update { $0.title = "On Plex" }.execute(db)
		}

		let updatedParagraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(updatedParagraph.string, "Saw Megalopolis #[[On Plex]]")

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId == paragraph.id }.fetchAll(db)
		}

		expectNoDifference(references, [
			Reference(id: UUID(4), sourceBlockId: paragraph.id, targetBlockId: tagPage.id, kind: .tag),
		])
	}

	@Test("Bracketed tags don't also create page link references")
	func bracketedTagsDontCreatePageLinkReferences() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Loved #[[Megalopolis]]", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let tagPage = try #require(database.read { db in
			try Page.where { $0.title == "Megalopolis" }.fetchOne(db)
		})

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId == paragraph.id }.fetchAll(db)
		}

		expectNoDifference(references, [
			Reference(id: UUID(3), sourceBlockId: paragraph.id, targetBlockId: tagPage.id, kind: .tag),
		])
	}

	@Test("Renaming a page updates all references in a block with mixed kinds")
	func renamingPageUpdatesAllReferencesInBlock() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let referencedPage = try #require(database.write { db in
			try Page.insert { Page(title: "Old") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Read [[Old]] and #Old and [[Old]] again", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(referencedPage.id).update { $0.title = "New Title" }.execute(db)
		}

		let updatedParagraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(updatedParagraph.string, "Read [[New Title]] and #[[New Title]] and [[New Title]] again")
	}

	@Test("Renaming a tag page to a simple title removes brackets")
	func renamingTagPageToSimpleTitleRemovesBrackets() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let tagPage = try #require(database.write { db in
			try Page.insert { Page(title: "Old Tag") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Watch #[[Old Tag]]", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(tagPage.id).update { $0.title = "NewTag" }.execute(db)
		}

		let updatedParagraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(updatedParagraph.string, "Watch #NewTag")
	}

	@Test("A page stripped of all its references properly deletes them")
	func deletingAllReferencesFromParagraphDeletesThem() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw [[Megalopolis]] again #onPlex", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(paragraph.id).update {
				$0.string = "Haven't seen any movies recently."
			}.execute(db)
		}

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId == paragraph.id }.fetchAll(db)
		}

		expectNoDifference(references, [])
	}
}
