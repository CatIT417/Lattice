import Foundation

extension String {
	func quoted() -> String {
		let escaped = replacingOccurrences(of: "\"", with: "\"\"")

		let segments = split(whereSeparator: \.isWhitespace).map {
			"""
			"\($0.replacingOccurrences(of: "\"", with: "\"\""))"
			"""
		}.joined(separator: " ")

		guard !segments.isEmpty else {
			// FTS does not accept an empty query or a bare whitespace string.
			return "\" \""
		}

		return "\(segments) OR \"\(escaped)\""
	}
}
