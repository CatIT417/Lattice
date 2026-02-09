import Foundation

/// Matches markdown links: `[text](url)`
struct LinkRule: InlineParser.Rule, Sendable {
	let priority = 600
	let startingCharacters: Set<Character>? = ["["]

	// Matches [text](url) where text and url are non-empty.
	// The label allows ] as long as it's not followed by ( (which signals the ](url) boundary).
	// The URL part supports one level of balanced parentheses (e.g. Wikipedia URLs).
	private nonisolated(unsafe) static let pattern = /\[((?:[^\]]|\](?!\())+)\]\(([^()\s]+(?:\([^()]*\)[^()\s]*)*)\)/

	private static let allowedSchemes: Set<String> = [
		"http", "https", "file",
	]

	func match(in text: String, at index: String.Index, using _: InlineParser) -> InlineSpan? {
		let remaining = text[index...]
		guard let match = remaining.prefixMatch(of: Self.pattern) else { return nil }

		let linkText = String(match.1)

		guard let url = URL(string: String(match.2)), let scheme = url.scheme, Self.allowedSchemes.contains(scheme.lowercased())
		else { return nil }

		return InlineSpan(
			kind: .link(url: url),
			range: match.range,
			content: linkText,
			children: InlineParser.formattingOnly.parse(linkText)
		)
	}
}
