import Foundation

extension String {
	func quoted() -> String {
		split(separator: " ").map {
			"""
			"\($0.replacingOccurrences(of: "\"", with: "\"\""))"
			"""
		}.joined(separator: " ")
	}
}
