import Foundation

extension Date {
	init(millisecondsSince1970: TimeInterval) {
		self = Date(timeIntervalSince1970: millisecondsSince1970 / 1000)
	}

	init(millisecondsSince1970: Int) {
		self.init(millisecondsSince1970: TimeInterval(millisecondsSince1970))
	}
}
