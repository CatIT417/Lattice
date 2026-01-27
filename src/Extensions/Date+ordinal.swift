import Foundation

fileprivate let formatter = tap(NumberFormatter()) { $0.numberStyle = .ordinal }

extension Date {
	var ordinal: String {
		let day = Calendar.current.component(.day, from: self)
		return formatter.string(from: NSNumber(value: day)) ?? ""
	}
}
