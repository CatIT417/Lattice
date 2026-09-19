import Testing
import Foundation
import CustomDump
@testable import LatticeDev
import Dependencies

extension Tests {
	@Suite("Support/DayOfYear")
	struct DayOfYearTest {}
}

extension Tests.DayOfYearTest {
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

	@Test("A stored day has the expected start instant in each time zone", arguments: [
		("Asia/Tokyo", 1_770_044_400.0),
		("America/Los_Angeles", 1_770_105_600.0),
		("Pacific/Kiritimati", 1_770_026_400.0),
	])
	func dateRoundTrip(timeZone: String, seconds: TimeInterval) throws {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = try #require(TimeZone(identifier: timeZone))
		let day = DayOfYear(day: 3, month: 2, year: 2026)
		let date = day.date(in: calendar)
		expectNoDifference(date, Date(timeIntervalSince1970: seconds))
		expectNoDifference(DayOfYear(date, calendar: calendar), day)
		expectNoDifference(day.rawValue, "2026-02-03")
		expectNoDifference(day.title, "February 3, 2026")
	}

	@Test("Default conversion matches the Gregorian calendar on this host")
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
		("2024-01-01", DayOfYear(day: 1, month: 1, year: 2024)),
		("2026-02-03", DayOfYear(day: 3, month: 2, year: 2026)),
		("2024-02-29", DayOfYear(day: 29, month: 2, year: 2024)),
	])
	func parsesTitle(title: String, expected: DayOfYear) {
		expectNoDifference(DayOfYear(rawValue: title), expected)
		expectNoDifference(DayOfYear(rawValue: title)?.rawValue, title)
	}

	@Test("rejects non-daily-page titles", arguments: [
		"Hello World",
		"02/03/2026",
		"February 3, 2026",
		"12 février 2026",
		"2026-02-29",
		"2026-02-30",
		"2026-00-05",
		"2026-13-05",
		"2026-09-00",
		"2026-9-05",
		"2026-09-5",
		"2026-09-05T00:00:00Z",
		" 2026-09-05",
	])
	func rejectsInvalidTitle(title: String) {
		#expect(DayOfYear(rawValue: title) == nil)
	}

	@Test("Display titles use the selected locale", arguments: [
		("en_US", "February 12, 2026"),
		("en_GB", "12 February 2026"),
		("fr_FR", "12 février 2026"),
		("de_DE", "12. Februar 2026"),
		("ja_JP", "2026年2月12日"),
	])
	func localizedTitle(localeIdentifier: String, expected: String) throws {
		let day = try #require(DayOfYear(rawValue: "2026-02-12"))
		withDependencies {
			$0.locale = Locale(identifier: localeIdentifier)
		} operation: {
			expectNoDifference(day.title, expected)
		}
		expectNoDifference(day.rawValue, "2026-02-12")
	}
}
