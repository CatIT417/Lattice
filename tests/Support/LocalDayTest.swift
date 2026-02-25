import Testing
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Support/DayOfYear")
	struct DayOfYearTest {}
}

extension Tests.DayOfYearTest {
	@Test("parses and formats day representation")
	func parseAndFormat() throws {
		let day = try #require(DayOfYear(rawValue: "2026-02-03"))
		expectNoDifference(day.rawValue, "2026-02-03")
	}

	@Test("extracting local day depends on chosen calendar timezone")
	func extractionUsesCalendarTimezone() {
		let date = Date(timeIntervalSince1970: 1_770_076_800) // 2026-02-03T00:00:00Z

		var utcCalendar = Calendar(identifier: .gregorian)
		utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

		var laCalendar = Calendar(identifier: .gregorian)
		laCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

		expectNoDifference(DayOfYear(date, calendar: utcCalendar), DayOfYear(day: 3, month: 2, year: 2026))
		expectNoDifference(DayOfYear(date, calendar: laCalendar), DayOfYear(day: 2, month: 2, year: 2026))
	}

	@Test("day to date conversion round-trips in the same calendar")
	func dateRoundTrip() {
		var tokyoCalendar = Calendar(identifier: .gregorian)
		tokyoCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

		let day = DayOfYear(day: 3, month: 2, year: 2026)
		let date = day.date(in: tokyoCalendar)

		expectNoDifference(DayOfYear(date, calendar: tokyoCalendar), day)
	}

	@Test("default conversion uses Gregorian calendar semantics")
	func defaultConversionUsesGregorian() {
		let date = Date(timeIntervalSince1970: 1_770_076_800) // 2026-02-03T00:00:00Z
		let timezone = TimeZone.autoupdatingCurrent

		var gregorian = Calendar(identifier: .gregorian)
		gregorian.timeZone = timezone

		var buddhist = Calendar(identifier: .buddhist)
		buddhist.timeZone = timezone

		expectNoDifference(DayOfYear(date), DayOfYear(date, calendar: gregorian))
		#expect(DayOfYear(date, calendar: buddhist) != DayOfYear(date, calendar: gregorian))
	}

	@Test("parses valid daily page titles", arguments: [
		("January 1st, 2024", DayOfYear(day: 1, month: 1, year: 2024)),
		("February 3rd, 2026", DayOfYear(day: 3, month: 2, year: 2026)),
		("December 22nd, 2025", DayOfYear(day: 22, month: 12, year: 2025)),
	])
	func parsesTitle(title: String, expected: DayOfYear) {
		expectNoDifference(DayOfYear(title: title), expected)
	}

	@Test("rejects non-daily-page titles", arguments: [
		"Hello World",
		"February 2026",
		"02/03/2026",
		"February 3, 2026",
		"February 33rd, 2026",
	])
	func rejectsInvalidTitle(title: String) {
		#expect(DayOfYear(title: title) == nil)
	}

	@Test("title round-trips through init(title:)")
	func titleRoundTrip() {
		let day = DayOfYear(day: 24, month: 2, year: 2026)
		expectNoDifference(DayOfYear(title: day.title()), day)
	}
}
