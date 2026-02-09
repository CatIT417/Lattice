import Foundation

/// Matches tags: `#tag` or `#[[tag with spaces]]`
struct TagRule: InlineParser.Rule, Sendable {
	let priority = 550
	let startingCharacters: Set<Character>? = ["#"]

	private nonisolated(unsafe) static let simplePattern = /#(\w+)/
	private nonisolated(unsafe) static let bracketedPattern = /#\[\[([^\]]+)\]\]/

	func match(in text: String, at index: String.Index, using _: InlineParser) -> InlineSpan? {
		let remaining = text[index...]

		if let match = remaining.prefixMatch(of: Self.bracketedPattern) {
			return extractTag(match: match)
		}

		if let match = remaining.prefixMatch(of: Self.simplePattern) {
			return extractTag(match: match)
		}

		return nil
	}

	private func extractTag(match: Regex<Regex<(Substring, Substring)>.RegexOutput>.Match) -> InlineSpan? {
		let target = String(match.1)
		guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

		return InlineSpan(
			kind: .tag,
			range: match.range,
			content: target,
			children: []
		)
	}
}
