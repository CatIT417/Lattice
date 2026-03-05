import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Result of building an attributed string, including the string and index mapping
struct AttributedStringResult {
	/// Maps character positions between rendered text (with links like "World") and raw text (with "[[World]]")
	struct IndexMapping {
		fileprivate let renderedToRaw: [Int]

		/// Convert a cursor position from rendered text to raw text position
		func rawIndex(fromRendered renderedIndex: Int) -> Int {
			guard renderedIndex >= 0 else { return 0 }
			guard renderedIndex < renderedToRaw.count else {
				return renderedToRaw.last ?? renderedIndex
			}
			return renderedToRaw[renderedIndex]
		}

		func transform(range: NSRange, maxLength: Int) -> NSRange {
			let start = min(rawIndex(fromRendered: range.location), maxLength)
			let end = min(rawIndex(fromRendered: range.location + range.length), maxLength)

			return NSRange(location: start, length: end - start)
		}
	}

	let indexMapping: IndexMapping?
	let uncachedFaviconURLs: Set<URL>
	let attributedString: NSAttributedString

	init(renderedToRaw: [Int]? = nil, attributedString: NSAttributedString, uncachedFaviconURLs: Set<URL> = []) {
		self.attributedString = attributedString
		self.uncachedFaviconURLs = uncachedFaviconURLs
		indexMapping = renderedToRaw.map { IndexMapping(renderedToRaw: $0) }
	}
}

func removeReferences(from text: String) -> String {
	var result = text
	let refs = text.extractRefs().sorted { $0.range.lowerBound > $1.range.lowerBound }

	for ref in refs {
		result.replaceSubrange(ref.range, with: ref.target)
	}

	return result
}

/// Characters that can start inline markup — if none are present, parsing can be skipped entirely.
private let inlineMarkupCharacters: Set<Character> = ["*", "_", "`", "=", "[", "(", "#"]

/// Build an NSAttributedString from text with refs and formatting
func buildAttributedString(from text: String, font: PlatformFont = .preferredFont(forTextStyle: .body), using parser: InlineParser = .default, rawStartOffset: Int = 0, faviconProvider: ((URL) -> PlatformImage?)? = nil) -> AttributedStringResult {
	let baseAttributes: [NSAttributedString.Key: Any] = [
		.font: font,
		.foregroundColor: labelColor,
	]

	// Fast path: skip parsing when no inline markup markers are present
	guard text.contains(where: { inlineMarkupCharacters.contains($0) }) || text.contains("://") else {
		return plainAttributedResult(for: text, attributes: baseAttributes, rawStartOffset: rawStartOffset)
	}

	let spans = parser.parse(text)

	// Check if there's any non-text content (markers were present but didn't form valid syntax)
	let hasFormatting = spans.contains { $0.kind != .text }
	if !hasFormatting {
		return plainAttributedResult(for: text, attributes: baseAttributes, rawStartOffset: rawStartOffset)
	}

	let result = NSMutableAttributedString()
	var renderedToRaw: [Int] = []
	renderedToRaw.reserveCapacity(text.utf16.count + 1)
	var uncachedFaviconURLs: Set<URL> = []

	let context = RenderContext(sourceText: text, rawStartOffset: rawStartOffset, attributes: baseAttributes, font: font, inheritedTraits: [], faviconProvider: faviconProvider)
	for span in spans {
		context.render(span: span, into: result, renderedToRaw: &renderedToRaw, uncachedFaviconURLs: &uncachedFaviconURLs)
	}

	// Add final position (for cursor at end)
	renderedToRaw.append(text.utf16.count + rawStartOffset)

	return AttributedStringResult(renderedToRaw: renderedToRaw, attributedString: result, uncachedFaviconURLs: uncachedFaviconURLs)
}

private func plainAttributedResult(for text: String, attributes: [NSAttributedString.Key: Any], rawStartOffset: Int = 0) -> AttributedStringResult {
	guard rawStartOffset > 0 else {
		return AttributedStringResult(attributedString: NSAttributedString(string: text, attributes: attributes))
	}

	// Build a simple identity mapping shifted by rawStartOffset
	var renderedToRaw: [Int] = []
	renderedToRaw.reserveCapacity(text.utf16.count + 1)
	for i in 0...text.utf16.count {
		renderedToRaw.append(i + rawStartOffset)
	}
	return AttributedStringResult(renderedToRaw: renderedToRaw, attributedString: NSAttributedString(string: text, attributes: attributes))
}

private struct RenderContext {
	let sourceText: String
	let rawStartOffset: Int
	let attributes: [NSAttributedString.Key: Any]
	let font: PlatformFont
	let inheritedTraits: PlatformFontDescriptor.SymbolicTraits
	let faviconProvider: ((URL) -> PlatformImage?)?
}

private struct RenderStyle {
	let baseAttributes: [NSAttributedString.Key: Any]
	let baseFont: PlatformFont
	let inheritedTraits: PlatformFontDescriptor.SymbolicTraits

	func withFont(_ font: PlatformFont) -> [NSAttributedString.Key: Any] {
		tap(baseAttributes) { $0[.font] = font }
	}

	func link(_ url: URL, embed: EmbedInfo? = nil) -> [NSAttributedString.Key: Any] {
		tap(baseAttributes) {
			$0[.link] = url
			$0[.foregroundColor] = tintColor

			if embed != nil {
				$0[.font] = baseFont.withSize(baseFont.pointSize * 0.9)
			}
		}
	}

	func highlight() -> [NSAttributedString.Key: Any] {
		tap(baseAttributes) {
			$0[.backgroundColor] = PlatformColor.systemYellow.withAlphaComponent(0.3)
		}
	}

	func code() -> [NSAttributedString.Key: Any] {
		tap(baseAttributes) {
			$0[.font] = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)

			#if canImport(UIKit)
			$0[.backgroundColor] = UIColor.secondarySystemFill
			#elseif canImport(AppKit)
			$0[.backgroundColor] = NSColor.unemphasizedSelectedContentBackgroundColor
			#endif
		}
	}

	func emphasis(_ trait: PlatformFontDescriptor.SymbolicTraits) -> (
		attributes: [NSAttributedString.Key: Any],
		font: PlatformFont,
		traits: PlatformFontDescriptor.SymbolicTraits
	) {
		let traits = inheritedTraits.union(trait)
		let font = baseFont.withTraits(traits)
		return (withFont(font), font, traits)
	}
}

private extension RenderContext {
	var style: RenderStyle {
		RenderStyle(baseAttributes: attributes, baseFont: font, inheritedTraits: inheritedTraits)
	}

	func render(span: InlineSpan, into result: NSMutableAttributedString, renderedToRaw: inout [Int], uncachedFaviconURLs: inout Set<URL>) {
		let spanRawStart = rawStart(for: span)

		switch span.kind {
			case .text: append(text: span.content, with: attributes, rawStart: spanRawStart, into: result, renderedToRaw: &renderedToRaw)
			case .pageLink, .tag, .blockRef, .blockEmbed: render(reference: span, spanRawStart: spanRawStart, into: result, renderedToRaw: &renderedToRaw)
			case .code: append(text: span.content, with: style.code(), rawStart: spanRawStart + 1, /* Skip opening ` */ into: result, renderedToRaw: &renderedToRaw)
			case .bold:
				render(
					emphasis: span,
					spanRawStart: spanRawStart,
					addingTrait: .traitBold,
					contentDelimiterLength: 2, // **
					into: result,
					renderedToRaw: &renderedToRaw,
					uncachedFaviconURLs: &uncachedFaviconURLs
				)
			case .italic:
				render(
					emphasis: span,
					spanRawStart: spanRawStart,
					addingTrait: .traitItalic,
					contentDelimiterLength: 1, // *
					into: result,
					renderedToRaw: &renderedToRaw,
					uncachedFaviconURLs: &uncachedFaviconURLs
				)
			case .highlight:
				render(
					container: span,
					spanRawStart: spanRawStart,
					contentDelimiterLength: 2, // ==
					childAttributes: style.highlight(),
					childFont: font,
					childTraits: inheritedTraits,
					into: result,
					renderedToRaw: &renderedToRaw,
					uncachedFaviconURLs: &uncachedFaviconURLs
				)
			case let .link(url, embed):
				let isExternal = url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"

				if isExternal, embed == nil {
					appendFavicon(for: url, linkAttributes: style.link(url), spanRawStart: spanRawStart, into: result, renderedToRaw: &renderedToRaw, uncachedFaviconURLs: &uncachedFaviconURLs)
				}

				if span.children.isEmpty {
					// Auto-link: rendered text = raw text, no delimiters
					append(text: span.content, with: style.link(url, embed: embed), rawStart: spanRawStart, into: result, renderedToRaw: &renderedToRaw)
				} else {
					// Markdown link: [text](url)
					render(
						container: span,
						spanRawStart: spanRawStart,
						contentDelimiterLength: 1, // [
						childAttributes: style.link(url),
						childFont: font,
						childTraits: inheritedTraits,
						into: result,
						renderedToRaw: &renderedToRaw,
						uncachedFaviconURLs: &uncachedFaviconURLs
					)
				}
		}
	}

	func render(
		emphasis span: InlineSpan,
		spanRawStart: Int,
		addingTrait trait: PlatformFontDescriptor.SymbolicTraits,
		contentDelimiterLength: Int,
		into result: NSMutableAttributedString,
		renderedToRaw: inout [Int],
		uncachedFaviconURLs: inout Set<URL>
	) {
		let emphasis = style.emphasis(trait)
		render(
			container: span,
			spanRawStart: spanRawStart,
			contentDelimiterLength: contentDelimiterLength,
			childAttributes: emphasis.attributes,
			childFont: emphasis.font,
			childTraits: emphasis.traits,
			into: result,
			renderedToRaw: &renderedToRaw,
			uncachedFaviconURLs: &uncachedFaviconURLs
		)
	}

	func render(
		container span: InlineSpan,
		spanRawStart: Int,
		contentDelimiterLength: Int,
		childAttributes: [NSAttributedString.Key: Any],
		childFont: PlatformFont,
		childTraits: PlatformFontDescriptor.SymbolicTraits,
		into result: NSMutableAttributedString,
		renderedToRaw: inout [Int],
		uncachedFaviconURLs: inout Set<URL>
	) {
		let contentRawStart = spanRawStart + contentDelimiterLength

		guard !span.children.isEmpty else {
			append(text: span.content, with: childAttributes, rawStart: contentRawStart, into: result, renderedToRaw: &renderedToRaw)
			return
		}

		let childContext = RenderContext(
			sourceText: span.content,
			rawStartOffset: contentRawStart,
			attributes: childAttributes,
			font: childFont,
			inheritedTraits: childTraits,
			faviconProvider: faviconProvider
		)

		for child in span.children {
			childContext.render(span: child, into: result, renderedToRaw: &renderedToRaw, uncachedFaviconURLs: &uncachedFaviconURLs)
		}
	}

	func render(
		reference span: InlineSpan,
		spanRawStart: Int,
		into result: NSMutableAttributedString,
		renderedToRaw: inout [Int]
	) {
		guard let ref = TextRef(from: span) else {
			append(text: span.content, with: attributes, rawStart: spanRawStart, into: result, renderedToRaw: &renderedToRaw)
			return
		}
		result.append(NSAttributedString(string: ref.prefix + span.content, attributes: style.link(ref.url)))

		let rawSpanText = String(sourceText[span.range])
		let bracketOffset = ref.kind.bracketOffset(for: rawSpanText)
		appendRawOffsets(for: ref.prefix, from: spanRawStart, into: &renderedToRaw)
		appendRawOffsets(for: span.content, from: spanRawStart + bracketOffset, into: &renderedToRaw)
	}

	func appendFavicon(
		for url: URL,
		linkAttributes: [NSAttributedString.Key: Any],
		spanRawStart: Int,
		into result: NSMutableAttributedString,
		renderedToRaw: inout [Int],
		uncachedFaviconURLs: inout Set<URL>
	) {
		guard let image = faviconProvider?(url) else {
			if let faviconURL = FaviconLoader.faviconURL(for: url) {
				uncachedFaviconURLs.insert(faviconURL)
			}
			return
		}

		let size = round(font.ascender - font.descender)
		let yOffset = round((font.capHeight - size) / 2)
		let attachment = NSMutableAttributedString(attachment: tap(NSTextAttachment()) {
			$0.image = image
			$0.bounds = CGRect(x: 0, y: yOffset, width: size, height: size)
		})

		attachment.addAttributes(linkAttributes, range: NSRange(location: 0, length: attachment.length))
		result.append(attachment)
		// \u{FFFC} = 1 UTF-16 unit, maps to span's raw start (phantom character)
		renderedToRaw.append(spanRawStart)

		result.append(NSAttributedString(string: " ", attributes: linkAttributes))
		// space = 1 UTF-16 unit, maps to span's raw start (phantom character)
		renderedToRaw.append(spanRawStart)
	}

	func append(text string: String, with attributes: [NSAttributedString.Key: Any], rawStart: Int, into result: NSMutableAttributedString, renderedToRaw: inout [Int]) {
		result.append(NSAttributedString(string: string, attributes: attributes))
		appendRawOffsets(for: string, from: rawStart, into: &renderedToRaw)
	}

	func appendRawOffsets(for renderedSegment: String, from rawStart: Int, into renderedToRaw: inout [Int]) {
		var rawOffset = rawStart
		for char in renderedSegment {
			let width = char.utf16.count
			for i in 0..<width {
				renderedToRaw.append(rawOffset + i)
			}
			rawOffset += width
		}
	}

	func rawStart(for span: InlineSpan) -> Int {
		rawStartOffset + sourceText.utf16.distance(from: sourceText.startIndex, to: span.range.lowerBound)
	}
}

// MARK: - Font Extensions

extension PlatformFont {
	/// Returns a new font with the specified traits added
	func withTraits(_ traits: PlatformFontDescriptor.SymbolicTraits) -> PlatformFont {
		#if canImport(UIKit)
		guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
			return self
		}
		return PlatformFont(descriptor: descriptor, size: pointSize)
		#elseif canImport(AppKit)
		let descriptor = fontDescriptor.withSymbolicTraits(traits)
		return PlatformFont(descriptor: descriptor, size: pointSize) ?? self
		#endif
	}
}

// MARK: - Symbolic Traits Compatibility

#if canImport(AppKit)
extension NSFontDescriptor.SymbolicTraits {
	static let traitBold: NSFontDescriptor.SymbolicTraits = .bold
	static let traitItalic: NSFontDescriptor.SymbolicTraits = .italic
}
#endif
