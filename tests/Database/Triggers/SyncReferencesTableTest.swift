import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SyncReferencesTable", .dependencies {
		try $0.bootstrapDatabase()
		$0.date = .constant(.distantPast)
	})
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
			try Page.where { $0.title.eq("Megalopolis") }.fetchOne(db)
		})

		let tagPage = try #require(database.read { db in
			try Page.where { $0.title.eq("onPlex") }.fetchOne(db)
		})

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
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
				$0.string = #bind("Saw [[Tenet]] once again")
			}.execute(db)
		}

		let newPage = try #require(database.read { db in
			try Page.where { $0.title.eq("Tenet") }.fetchOne(db)
		})

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
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
			try Block.find(referencedPage.id).update { $0.title = #bind("Megalopolis") }.execute(db)
		}

		let updatedParagraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(updatedParagraph.string, "Saw [[Megalopolis]]")

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
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
			try Block.find(tagPage.id).update { $0.title = #bind("On Plex") }.execute(db)
		}

		let updatedParagraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(updatedParagraph.string, "Saw Megalopolis #[[On Plex]]")

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
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
			try Page.where { $0.title.eq("Megalopolis") }.fetchOne(db)
		})

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
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
			try Block.find(referencedPage.id).update { $0.title = #bind("New Title") }.execute(db)
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
			try Block.find(tagPage.id).update { $0.title = #bind("NewTag") }.execute(db)
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
				$0.string = #bind("Haven't seen any movies recently.")
			}.execute(db)
		}

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
		}

		expectNoDifference(references, [])
	}

	@Test("Deleting a page removes all references")
	func deletingAPageRemovesAllReferences() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		var paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw [[Megalopolis]] again", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		let referencePage = try #require(database.read { db in
			try Page.where { $0.title.eq("Megalopolis") }.fetchOne(db)
		})

		try database.write { db in
			try Block.find(referencePage.id).delete().execute(db)
		}

		let references = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(paragraph.id) }.fetchAll(db)
		}

		expectNoDifference(references, [])

		paragraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(paragraph.string, "Saw Megalopolis again")
	}

	@Test("Deleting a page removes tag syntax with leading space")
	func deletingPageRemovesTagWithLeadingSpace() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let tagPage = try #require(database.write { db in
			try Page.insert { Page(title: "cinema") }.returning(\.self).fetchOne(db)
		})

		var paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw Megalopolis #cinema", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(tagPage.id).delete().execute(db)
		}

		paragraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(paragraph.string, "Saw Megalopolis")
	}

	@Test("Deleting a page removes tag syntax with trailing space")
	func deletingPageRemovesTagWithTrailingSpace() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let tagPage = try #require(database.write { db in
			try Page.insert { Page(title: "cinema") }.returning(\.self).fetchOne(db)
		})

		var paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "#cinema is great", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(tagPage.id).delete().execute(db)
		}

		paragraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(paragraph.string, "is great")
	}

	@Test("Deleting a page removes bracketed tag syntax")
	func deletingPageRemovesBracketedTag() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let tagPage = try #require(database.write { db in
			try Page.insert { Page(title: "On Plex") }.returning(\.self).fetchOne(db)
		})

		var paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw Megalopolis #[[On Plex]]", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(tagPage.id).delete().execute(db)
		}

		paragraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(paragraph.string, "Saw Megalopolis")
	}

	@Test("Deleting a page cleans up mixed reference kinds")
	func deletingPageCleansMixedReferences() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let referencedPage = try #require(database.write { db in
			try Page.insert { Page(title: "Old") }.returning(\.self).fetchOne(db)
		})

		var paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Read [[Old]] and #Old and [[Old]] again", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(referencedPage.id).delete().execute(db)
		}

		paragraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(paragraph.string, "Read Old and and Old again")
	}

	@Test("Deleting a page cleans up references across multiple blocks")
	func deletingPageCleansMultipleBlocks() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		var paragraph1 = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Saw [[Megalopolis]]", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		var paragraph2 = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Also [[Megalopolis]] was good", parentId: hostPage.id, pageId: hostPage.id, order: 1)
			}.returning(\.self).fetchOne(db)
		})

		let referencePage = try #require(database.read { db in
			try Page.where { $0.title.eq("Megalopolis") }.fetchOne(db)
		})

		try database.write { db in
			try Block.find(referencePage.id).delete().execute(db)
		}

		paragraph1 = try #require(database.read { db in
			try Paragraph.find(paragraph1.id).fetchOne(db)
		})

		paragraph2 = try #require(database.read { db in
			try Paragraph.find(paragraph2.id).fetchOne(db)
		})

		expectNoDifference(paragraph1.string, "Saw Megalopolis")
		expectNoDifference(paragraph2.string, "Also Megalopolis was good")
	}

	@Test("Deleting a page with a sole tag reference leaves empty string")
	func deletingPageWithSoleTagLeavesEmptyString() throws {
		let hostPage = try #require(database.write { db in
			try Page.insert { Page(title: "Favourite Movies") }.returning(\.self).fetchOne(db)
		})

		let tagPage = try #require(database.write { db in
			try Page.insert { Page(title: "cinema") }.returning(\.self).fetchOne(db)
		})

		var paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "#cinema", parentId: hostPage.id, pageId: hostPage.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(tagPage.id).delete().execute(db)
		}

		paragraph = try #require(database.read { db in
			try Paragraph.find(paragraph.id).fetchOne(db)
		})

		expectNoDifference(paragraph.string, "")
	}
}
