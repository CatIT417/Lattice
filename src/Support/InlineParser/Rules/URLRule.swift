import Foundation

/// Matches plain URLs: `https://example.com` or `http://example.com`
struct URLRule: InlineParser.Rule, Sendable {
	let priority = 580 // between LinkRule (600) and TagRule (550)
	let startingCharacters: Set<Character>? = ["h", "H"]

	/// Greedily matches http:// or https:// (case-insensitive) followed by valid URL characters.
	/// Allows brackets for IPv6 hosts and array-style query params (e.g. `?filters[]=done`).
	/// Post-processing strips trailing punctuation while preserving balanced parentheses and brackets.
	private nonisolated(unsafe) static let pattern = /(?i:https?):\/\/[^\s<>]+/

	private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", "'", "\""]

	func match(in text: String, at index: String.Index, using _: InlineParser) -> InlineSpan? {
		let remaining = text[index...]

		guard let match = remaining.prefixMatch(of: Self.pattern) else { return nil }

		let urlString = Self.stripTrailingPunctuation(String(match.output))
		guard !urlString.hasSuffix("://"), // reject bare "http(s)://"
		      let url = URL(string: urlString) else { return nil }

		let endIndex = text.index(index, offsetBy: urlString.count)

		return InlineSpan(
			kind: .link(url: url),
			range: index..<endIndex,
			content: urlString,
			children: []
		)
	}

	/// Strip trailing sentence punctuation, preserving balanced parentheses.
	private static func stripTrailingPunctuation(_ url: String) -> String {
		var chars = Array(url)

		while let last = chars.last {
			if trailingPunctuation.contains(last) {
				chars.removeLast()
			} else if last == ")" {
				// Only strip ) when unbalanced (more close than open)
				if chars.count(where: { $0 == ")" }) > chars.count(where: { $0 == "(" }) {
					chars.removeLast()
				} else { break }
			} else if last == "]" {
				// Only strip ] when unbalanced (more close than open)
				if chars.count(where: { $0 == "]" }) > chars.count(where: { $0 == "[" }) {
					chars.removeLast()
				} else { break }
			} else { break }
		}

		return String(chars)
	}
}
