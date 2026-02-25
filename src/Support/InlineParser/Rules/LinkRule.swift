import Foundation

/// Matches markdown links: `[text](url)` or `[text]([[page]])` / `[text](((uuid)))` / `[text](#tag)`
struct LinkRule: InlineParser.Rule, Sendable {
	let priority = 600
	let startingCharacters: Set<Character>? = ["["]

	// Matches [text](url) where text and url are non-empty.
	// The label allows ] as long as it's not followed by ( (which signals the ](url) boundary).
	// The URL part supports one level of balanced parentheses (e.g. Wikipedia URLs).
	private nonisolated(unsafe) static let pattern = /\[((?:[^\]]|\](?!\())+)\]\(([^()\s]+(?:\([^()]*\)[^()\s]*)*)\)/

	// Matches [text]([[page]]), [text](((uuid))), [text](#tag), [text](#[[tag]])
	private nonisolated(unsafe) static let internalRefPattern =
		/\[((?:[^\]]|\](?!\())+)\]\((\[\[[^\]]{3,}\]\]|\(\([a-fA-F0-9-]{36}\)\)|#\[\[[^\]]{3,}\]\]|#[A-Za-z0-9_-]{3,})\)/

	private static let allowedSchemes: Set<String> = [
		"http", "https", "file",
	]

	func match(in text: String, at index: String.Index, using _: InlineParser) -> InlineSpan? {
		let remaining = text[index...]

		// Try external URL pattern first
		if let match = remaining.prefixMatch(of: Self.pattern), let url = URL(string: String(match.2)), let scheme = url.scheme, Self.allowedSchemes.contains(scheme.lowercased()) {
			return InlineSpan(
				kind: .link(url: url),
				range: match.range,
				content: String(match.1),
				children: InlineParser.formattingOnly.parse(String(match.1))
			)
		}

		// Try internal reference pattern
		guard let match = remaining.prefixMatch(of: Self.internalRefPattern) else { return nil }

		let linkText = String(match.1)
		let destination = String(match.2)

		guard let url = Self.parseInternalDestination(destination, in: match.range) else { return nil }

		return InlineSpan(
			kind: .link(url: url),
			range: match.range,
			content: linkText,
			children: InlineParser.formattingOnly.parse(linkText)
		)
	}

	/// Parse an internal reference destination into a lattice:// URL
	private static func parseInternalDestination(_ destination: String, in range: Range<String.Index>) -> URL? {
		guard let (kind, target) = InlineSpan.Kind.fromRefDestination(destination), let refKind = kind.asReferenceKind else { return nil }
		return TextRef(target: target, kind: refKind, range: range).url
	}
}
