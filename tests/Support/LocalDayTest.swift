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
		("2024-01-01", DayOfYear(day: 1, month: 1, year: 2024)),
		("2026-02-03", DayOfYear(day: 3, month: 2, year: 2026)),
		("2025-12-22", DayOfYear(day: 22, month: 12, year: 2025)),
		("2026-09-05", DayOfYear(day: 5, month: 9, year: 2026)),
		("2024-02-29", DayOfYear(day: 29, month: 2, year: 2024)),
	])
	func parsesTitle(title: String, expected: DayOfYear) {
		expectNoDifference(DayOfYear(rawValue: title), expected)
	}

	@Test("rejects non-daily-page titles", arguments: [
		"Hello World",
		"February 2026",
		"02/03/2026",
		"February 3, 2026",
		"February 33rd, 2026",
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

	@Test("Display text does not determine daily-note identity", arguments: ["February 12, 2026", "February 12th, 2026", "12 février 2026"])
	func rejectsDisplayTitles(title: String) {
		#expect(DayOfYear(rawValue: title) == nil)
	}

	@Test("Travel changes today without changing a stored day", arguments: ["America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati"])
	func storedDaySurvivesTravel(timeZone: String) throws {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = try #require(TimeZone(identifier: timeZone))
		let day = try #require(DayOfYear(rawValue: "2026-02-12"))
		expectNoDifference(DayOfYear(day.date(in: calendar), calendar: calendar).rawValue, "2026-02-12")
		expectNoDifference(day.title, "February 12, 2026")
	}

	@Test("Stored dates reject invalid and noncanonical values", arguments: ["2026-02-30", "2026-02-29", "2026-9-05", "2026-09-5"])
	func rejectsInvalidRawValue(value: String) {
		#expect(DayOfYear(rawValue: value) == nil)
	}
}
