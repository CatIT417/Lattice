import Foundation

extension Calendar {
	init(identifier: Calendar.Identifier, timezone: TimeZone) {
		var calendar = Calendar(identifier: identifier)
		calendar.timeZone = timezone
		self = calendar
	}
}
