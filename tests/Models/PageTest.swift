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
	@MainActor @Test("Display titles use the session locale and storage keeps the canonical title", arguments: [
		("en_US", "February 12, 2026"),
		("en_GB", "12 February 2026"),
		("fr_FR", "12 février 2026"),
		("ja_JP", "2026年2月12日"),
	])
	func titleProperties(localeIdentifier: String, expected: String) throws {
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

	@Test("Creating a daily note page sets the correct title and date")
	func dailyNoteCreation() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page.newDailyNote(for: DayOfYear(day: 3, month: 2, year: 2026)) }.returning(\.self).fetchOne(db)
		})

		expectNoDifference("2026-02-03", page.canonicalTitle)
		expectNoDifference(DayOfYear(day: 3, month: 2, year: 2026), page.dailyNoteDate)
	}

	@Test("Concurrent daily note requests return the same page")
	func concurrentDailyNoteCreation() async throws {
		let day = DayOfYear(day: 13, month: 9, year: 2026)
		async let firstRequest = database.write { try Page.createDailyNote(for: day, in: $0) }
		async let secondRequest = database.write { try Page.createDailyNote(for: day, in: $0) }
		let (first, second) = try await (firstRequest, secondRequest)

		expectNoDifference(first, second)
		let pages = try await database.read { try Page.fetchAll($0) }
		expectNoDifference(pages, [first])
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
		let after = try await database.read { try Block.order(by: \.id).fetchAll($0) }
		expectNoDifference(after, before)
	}

	@Test("Creating a page with an invalid title fails", arguments: ["AB", " AB ", "Bad [Title", "Bad ]Title"])
	func invalidTitle(title: String) throws {
		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Page.insert { Page(title: title) }.execute(db)
			}
		}
	}

	@Test("Creating a page with a title of exactly 3 characters succeeds")
	func minimumTitleLengthBoundary() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page(title: "ABC") }.returning(\.self).fetchOne(db)
		})

		expectNoDifference("ABC", page.canonicalTitle)
	}

	@Test("An invalid rename preserves the page title", arguments: ["AB", "Bad [Title", "Bad ]Title"])
	func invalidRename(title: String) throws {
		try database.write { db in
			try Page.insert { Page(title: "Test Page") }.execute(db)
		}

		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Block.where { $0.title.eq("Test Page") }
					.update { $0.title = #bind(title) }
					.execute(db)
			}
		}
		expectNoDifference(try database.read { try Page.fetchOne($0)?.canonicalTitle }, "Test Page")
	}

	@Test("Page.findOrCreate returns an existing page if one exists, otherwise creates it")
	func findOrCreate() throws {
		let page = try database.write { db in
			try Page.findOrCreate(title: "Unique Page", in: db)
		}

		let secondPage = try database.write { db in
			try Page.findOrCreate(title: "Unique Page", in: db)
		}

		expectNoDifference(page.id, secondPage.id)
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
