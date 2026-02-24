import Foundation

/// A parsed inline span representing either plain text, a reference, or formatted text
struct InlineSpan: Equatable, Sendable {
	/// The kind of inline span
	enum Kind: Equatable, Sendable {
		case text

		case code
		case bold
		case italic
		case highlight
		case link(url: URL)

		case tag
		case pageLink
		case blockRef
		case blockEmbed
	}

	/// The kind of span
	let kind: Kind

	/// Position in the raw text (including delimiters)
	let range: Range<String.Index>

	/// The text content without delimiters
	let content: String

	/// Nested spans (empty for leaf nodes like code or text)
	let children: [InlineSpan]

	init(kind: Kind, range: Range<String.Index>, content: String, children: [InlineSpan] = []) {
		self.kind = kind
		self.range = range
		self.content = content
		self.children = children
	}
}

extension InlineSpan.Kind {
	/// Whether this kind represents a reference (page link, tag, block ref, etc.)
	var isReference: Bool {
		switch self {
			case .pageLink, .tag, .blockRef, .blockEmbed: true
			default: false
		}
	}

	/// Convert to Reference.Kind if this is a reference type
	var asReferenceKind: Reference.Kind? {
		switch self {
			case .tag: .tag
			case .pageLink: .pageLink
			case .blockRef: .blockRef
			case .blockEmbed: .blockEmbed
			default: nil
		}
	}

	static func fromRefDestination(_ destination: String) -> (kind: Self, target: String)? {
		// page link (`[[page]]`)
		if destination.hasPrefix("[["), destination.hasSuffix("]]") {
			let title = String(destination.dropFirst(2).dropLast(2))
			guard !title.isEmpty, title.contains(where: { !$0.isWhitespace }) else { return nil }
			return (.pageLink, title)
		}

		// block link (`((uuid))`)
		if destination.hasPrefix("(("), destination.hasSuffix("))") {
			let raw = String(destination.dropFirst(2).dropLast(2))
			guard let uuid = UUID(uuidString: raw) else { return nil }
			return (.blockRef, uuid.uuidString)
		}

		// tag (`#[[tag]]`)
		if destination.hasPrefix("#[["), destination.hasSuffix("]]") {
			let tag = String(destination.dropFirst(3).dropLast(2))
			guard !tag.isEmpty, tag.contains(where: { !$0.isWhitespace }) else { return nil }
			return (.tag, tag)
		}

		// tag (`#tag`)
		if destination.hasPrefix("#") {
			let tag = String(destination.dropFirst())
			guard !tag.isEmpty else { return nil }
			return (.tag, tag)
		}

		return nil
	}
}
