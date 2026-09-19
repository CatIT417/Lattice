import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Models/Page", .dependencies { try $0.bootstrapDatabase() })
	struct PageTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.PageTest {
	@MainActor @Test("Display titles use the session locale and storage keeps the canonical title")
	func titleProperties() throws {
		let localeIdentifier = "fr_FR"
		let expected = "12 février 2026"
		try withDependencies {
			$0.locale = Locale(identifier: localeIdentifier)
		} operation: {
			let page = try database.write { db in
				let page = try Page.createDailyNote(for: DayOfYear(day: 12, month: 2, year: 2026), in: db)
				let block = try #require(try Block.find(page.id).fetchOne(db))
				let paragraph = Block(string: "See [[2026-02-12]]", parentId: page.id)
				try Block.insert { paragraph }.execute(db)

				expectNoDifference(page.canonicalTitle, "2026-02-12")
				expectNoDifference(page.title, expected)
				expectNoDifference(block.title, page.canonicalTitle)
				expectNoDifference(Page(block: block)?.title, expected)
				expectNoDifference(try #sql("SELECT title FROM pages", as: String.self).fetchOne(db), page.canonicalTitle)
				expectNoDifference(try Page.where { $0.canonicalTitle.eq("2026-02-12") }.fetchOne(db), page)

				let breadcrumb = try #require(try Breadcrumb.forBlock(id: paragraph.id).fetchOne(db))
				expectNoDifference(breadcrumb.canonicalTitle, page.canonicalTitle)
				expectNoDifference(breadcrumb.title, expected)
				let backlink = try #require(try Backlink.groupedByPage(forBlock: page.id).fetchOne(db))
				expectNoDifference(backlink.canonicalPageTitle, page.canonicalTitle)
				expectNoDifference(backlink.pageTitle, expected)
				let suggestion = ReferenceSuggestions.Item(canonicalTitle: page.canonicalTitle, isSyntheticNewPage: false)
				expectNoDifference(suggestion.title, expected)
				return page
			}
			#expect(try MarkdownExporter.exportPage(id: page.id).hasPrefix("# 2026-02-12\n"))
		}
	}

	@Test("Repeated daily note requests preserve the page and its contents")
	func dailyNoteCreationPreservesContent() async throws {
		let day = DayOfYear(day: 13, month: 9, year: 2026)
		let page = try await database.write { db in
			let page = try Page.createDailyNote(for: day, in: db)
			try Paragraph.insert { Paragraph(string: "Keep this note", parentId: page.id, pageId: page.id, order: 0) }.execute(db)
			return page
		}
		let before = try await database.read { try Block.order(by: \.id).fetchAll($0) }
		let later = page.createdAt.addingTimeInterval(60)

		let existing = try await database.write {
			try Page.createDailyNote(for: day, createdAt: later, updatedAt: later, in: $0)
		}

		expectNoDifference(existing.id, page.id)
		expectNoDifference(existing.canonicalTitle, "2026-09-13")
		expectNoDifference(existing.dailyNoteDate, day)
		let after = try await database.read { try Block.order(by: \.id).fetchAll($0) }
		expectNoDifference(after, before)
	}

	@Test("Invalid inserts and renames preserve stored pages", arguments: [
		("AB", Page.TitleError.tooShort), (" AB ", .tooShort),
		("Bad [Title", .containsBrackets), ("Bad ]Title", .containsBrackets),
	], [false, true])
	func invalidTitle(input: (String, Page.TitleError), rename: Bool) throws {
		let (title, expected) = input
		try database.write { db in
			if rename { try Page.insert { Page(title: "Test Page") }.execute(db) }
		}
		let before = try database.read { try Block.fetchAll($0) }
		do {
			try database.write { db in
				if rename {
					try Block.where { $0.title.eq("Test Page") }.update { $0.title = #bind(title) }.execute(db)
				} else {
					try Page.insert { Page(title: title) }.execute(db)
				}
			}
			Issue.record("The invalid title must be rejected.")
		} catch let error as DatabaseError {
			expectNoDifference(error.message, expected.localizedDescription)
		}
		expectNoDifference(try database.read { try Block.fetchAll($0) }, before)
	}

	@Test("Creating a page with a title of exactly 3 characters succeeds")
	func minimumTitleLengthBoundary() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "ABC") }.returning(\.self).fetchOne(db)
		})

		expectNoDifference("ABC", page.canonicalTitle)
	}

	@Test("Repeated findOrCreate calls preserve one page and its contents")
	func findOrCreate() throws {
		try database.write { db in
			let page = try Page.findOrCreate(title: "Unique Page", in: db)
			let child = Paragraph(string: "Keep this", parentId: page.id, pageId: page.id, order: 0)
			try Paragraph.insert { child }.execute(db)
			let before = try Block.order(by: \.id).fetchAll(db)
			let existing = try Page.findOrCreate(title: "Unique Page", in: db)
			expectNoDifference(existing.id, page.id)
			expectNoDifference(try Page.fetchCount(db), 1)
			expectNoDifference(try Block.order(by: \.id).fetchAll(db), before)
		}
	}

	@Test("Page.findOrCreate uses the canonical daily-note title")
	func findOrCreateDailyNoteTitle() throws {
		let day = DayOfYear(day: 5, month: 9, year: 2026)

		let page = try database.write { db in
			try Page.findOrCreate(title: day.rawValue, in: db)
		}
		expectNoDifference(page.dailyNoteDate, day)

		let dailyNote = try database.write { db in
			try Page.createDailyNote(for: day, in: db)
		}
		expectNoDifference(dailyNote.id, page.id)
	}
}
