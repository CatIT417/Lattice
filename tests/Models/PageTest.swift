import Testing
import SQLiteData
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Models/Page")
	struct PageTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.PageTest {
	@Test("Creating a daily note page sets the correct title and date")
	func dailyNoteCreation() throws {
		let page = try #require(database.write { db in
			try Page.insert { Page.newDailyNote(for: Date(timeIntervalSince1970: 1_770_098_996)) }.returning(\.self).fetchOne(db)
		})

		expectNoDifference("February 2nd, 2026", page.title)
		expectNoDifference(Date(timeIntervalSince1970: 1_770_019_200), page.dailyNoteDate)
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
