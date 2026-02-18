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
}
