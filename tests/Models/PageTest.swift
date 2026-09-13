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
	@Test("Creating a daily note page sets the correct title and date")
	func dailyNoteCreation() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page.newDailyNote(for: DayOfYear(day: 3, month: 2, year: 2026)) }.returning(\.self).fetchOne(db)
		})

		expectNoDifference("February 3rd, 2026", page.title)
		expectNoDifference(DayOfYear(day: 3, month: 2, year: 2026), page.dailyNoteDate)
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

		expectNoDifference("ABC", page.title)
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
		expectNoDifference(try database.read { try Page.fetchOne($0)?.title }, "Test Page")
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

	@Test("Page.findOrCreate treats both date formats as the daily note", arguments: [false, true])
	func findOrCreateDailyNoteTitle(useISO: Bool) throws {
		let day = DayOfYear(day: 5, month: 9, year: 2026)

		let page = try database.write { db in
			try Page.findOrCreate(title: useISO ? day.rawValue : day.title(), in: db)
		}
		expectNoDifference(page.dailyNoteDate, day)

		let dailyNote = try database.write { db in
			try Page.createDailyNote(for: day, in: db)
		}
		expectNoDifference(dailyNote.id, page.id)
	}
}
