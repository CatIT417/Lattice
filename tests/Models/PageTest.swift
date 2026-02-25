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

	@Test("Creating a page with a title shorter than 3 characters fails")
	func minimumTitleLength() throws {
		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Page.insert { Page(title: "AB") }.execute(db)
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

	@Test("Renaming a page to a title shorter than 3 characters fails")
	func renamingBelowMinimumLength() throws {
		try database.write { db in
			try Page.insert { Page(title: "Test Page") }.execute(db)
		}

		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Page.where { $0.title.eq("Test Page") }
					.update { $0.title = #bind("AB") }
					.execute(db)
			}
		}
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
}
