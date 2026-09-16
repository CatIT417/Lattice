import Foundation
import SQLiteData

struct DayOfYear: RawRepresentable, Equatable, Hashable, Sendable, Comparable {
	private let day: Int
	private let year: Int
	private let month: Int

	static var today: DayOfYear {
		@Dependency(\.date.now) var now
		return DayOfYear(now)
	}

	init(day: Int, month: Int, year: Int) {
		self.day = day
		self.year = year
		self.month = month
	}

	init(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian, timezone: .autoupdatingCurrent)) {
		let components = calendar.dateComponents([.day, .month, .year], from: date)

		self.init(day: components.day!, month: components.month!, year: components.year!)
	}

	init?(rawValue: String) {
		guard rawValue.utf8.count == 10 else { return nil }
		let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
		guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }

		let components = tap(DateComponents()) {
			$0.day = day
			$0.year = year
			$0.month = month
			$0.timeZone = TimeZone(secondsFromGMT: 0)
			$0.calendar = Calendar(identifier: .gregorian)
		}

		guard components.isValidDate else { return nil }
		self.init(day: day, month: month, year: year)
		guard self.rawValue == rawValue else { return nil }
	}

	var rawValue: String {
		String(format: "%04d-%02d-%02d", year, month, day)
	}

	func date(in calendar: Calendar = Calendar(identifier: .gregorian, timezone: .autoupdatingCurrent)) -> Date {
		let components = tap(DateComponents()) {
			$0.day = day
			$0.year = year
			$0.month = month
			$0.calendar = calendar
			$0.timeZone = calendar.timeZone
		}

		return calendar.startOfDay(for: components.date!)
	}

	var title: String {
		@Dependency(\.locale) var locale
		let calendar = Calendar(identifier: .gregorian, timezone: .gmt)

		return date(in: calendar).formatted(Date.FormatStyle(
			date: .long, time: .omitted,
			locale: Locale(identifier: locale.identifier),
			calendar: calendar, timeZone: .gmt
		))
	}

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

extension DayOfYear: QueryRepresentable, QueryBindable, QueryDecodable, SQLiteType {
	struct InvalidDay: Error {
		let string: String
	}

	var queryOutput: DayOfYear { self }
	var queryBinding: QueryBinding { .text(rawValue) }
	static var typeAffinity: SQLiteTypeAffinity { String.typeAffinity }

	init(decoder: inout some QueryDecoder) throws {
		let dayString = try String(decoder: &decoder)
		guard let day = DayOfYear(rawValue: dayString) else {
			throw InvalidDay(string: dayString)
		}

		self.init(queryOutput: day)
	}

	init(queryOutput: DayOfYear) {
		self = queryOutput
	}
}
