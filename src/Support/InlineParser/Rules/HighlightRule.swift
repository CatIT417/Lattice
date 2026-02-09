import Foundation

/// Matches highlighted text: ==text==
struct HighlightRule: InlineParser.Rule, Sendable {
	let priority = 200
	let startingCharacters: Set<Character>? = ["="]

	private nonisolated(unsafe) static let pattern = /==(\S(?:.*?\S)?)==/

	func match(in text: String, at index: String.Index, using parser: InlineParser) -> InlineSpan? {
		let remaining = text[index...]
		guard let match = remaining.prefixMatch(of: Self.pattern) else { return nil }

		let content = String(match.1)

		return InlineSpan(
			kind: .highlight,
			range: match.range,
			content: content,
			children: parser.parse(content)
		)
	}
}
