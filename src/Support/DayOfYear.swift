import Foundation
import SQLiteData

fileprivate let ordinalFormatter = tap(NumberFormatter()) {
	$0.numberStyle = .ordinal
}

struct DayOfYear: Equatable, Hashable, Sendable, Comparable {
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

	init(_ date: Date, calendar: Calendar = Self.gregorianCalendar(timeZone: .autoupdatingCurrent)) {
		let components = calendar.dateComponents([.day, .month, .year], from: date)

		self.init(day: components.day!, month: components.month!, year: components.year!)
	}

	init?(rawValue: String) {
		let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
		guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }

		let components = tap(DateComponents()) {
			$0.day = day
			$0.year = year
			$0.month = month
			$0.timeZone = TimeZone(secondsFromGMT: 0)
			$0.calendar = Calendar(identifier: .gregorian)
		}

		guard components.date != nil else { return nil }
		self.init(day: day, month: month, year: year)
	}

	var rawValue: String {
		String(format: "%04d-%02d-%02d", year, month, day)
	}

	func date(in calendar: Calendar = Self.gregorianCalendar(timeZone: .autoupdatingCurrent)) -> Date {
		let components = tap(DateComponents()) {
			$0.day = day
			$0.year = year
			$0.month = month
			$0.calendar = calendar
			$0.timeZone = calendar.timeZone
		}

		return calendar.startOfDay(for: components.date!)
	}

	func title(using calendar: Calendar = Self.gregorianCalendar(timeZone: .autoupdatingCurrent)) -> String {
		let date = date(in: calendar)

		let titleFormatter = tap(DateFormatter()) {
			$0.dateFormat = "MMMM '<dth>', yyyy"
			$0.calendar = calendar
			$0.timeZone = calendar.timeZone
		}

		return tap(titleFormatter.string(from: date)) {
			if $0.contains("<dth>"), let ordinal = ordinalFormatter.string(from: NSNumber(value: day)) { $0.replace("<dth>", with: ordinal) }
		}
	}

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	fileprivate static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = timeZone
		return calendar
	}
}

extension DayOfYear: QueryRepresentable, QueryBindable, QueryDecodable, SQLiteType {
	struct InvalidDay: Error {
		let string: String
	}

	var queryOutput: DayOfYear {
		self
	}

	static var typeAffinity: SQLiteTypeAffinity {
		String.typeAffinity
	}

	var queryBinding: QueryBinding {
		.text(rawValue)
	}

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
