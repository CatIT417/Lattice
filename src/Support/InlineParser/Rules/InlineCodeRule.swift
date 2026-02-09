import Foundation

/// Matches inline code spans: `code`
struct InlineCodeRule: InlineParser.Rule, Sendable {
	let priority = 1000
	let startingCharacters: Set<Character>? = ["`"]

	private nonisolated(unsafe) static let pattern = /`([^`]+)`/

	func match(in text: String, at index: String.Index, using _: InlineParser) -> InlineSpan? {
		let remaining = text[index...]
		guard let match = remaining.prefixMatch(of: Self.pattern) else { return nil }

		return InlineSpan(kind: .code, range: match.range, content: String(match.1), children: [])
	}
}
