import Foundation

/// Matches page links: `[[Page Name]]`
struct PageLinkRule: InlineParser.Rule, Sendable {
	let priority = 500
	let startingCharacters: Set<Character>? = ["["]

	private nonisolated(unsafe) static let pattern = /\[\[([^\]]+)\]\]/

	func match(in text: String, at index: String.Index, using _: InlineParser) -> InlineSpan? {
		let remaining = text[index...]
		guard let match = remaining.prefixMatch(of: Self.pattern) else { return nil }

		let target = String(match.1)
		guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

		return InlineSpan(
			kind: .pageLink,
			range: match.range,
			content: target,
			children: []
		)
	}
}
