import Foundation

/// Matches block references: ((uuid))
struct BlockRefRule: InlineParser.Rule, Sendable {
	let priority = 400
	let startingCharacters: Set<Character>? = ["("]

	// Matches ((uuid)) where uuid is a valid UUID format
	private nonisolated(unsafe) static let pattern = /\(\(([a-fA-F0-9-]{36})\)\)/

	func match(in text: String, at index: String.Index, using _: InlineParser) -> InlineSpan? {
		let remaining = text[index...]
		guard let match = remaining.prefixMatch(of: Self.pattern), let uuid = UUID(uuidString: String(match.1)) else { return nil }

		return InlineSpan(
			kind: .blockRef,
			range: match.range,
			content: uuid.uuidString,
			children: [] // Block refs don't have children
		)
	}
}
