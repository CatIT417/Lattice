import Foundation

/// A token-based inline parser that produces a tree of InlineSpan nodes
struct InlineParser: Sendable {
	protocol Rule {
		/// Priority determines matching order (higher = matched first)
		var priority: Int { get }

		/// Optional start-character filter used to skip irrelevant rules quickly.
		/// Return nil to match against all characters.
		var startingCharacters: Set<Character>? { get }

		/// Try to match at the current position. Returns nil if no match.
		/// The parser parameter allows rules to recursively parse content.
		func match(in text: String, at index: String.Index, using parser: InlineParser) -> InlineSpan?
	}

	/// Rules grouped by start character, each list already sorted by priority (highest first).
	private let rulesByStartingCharacter: [Character: [any Rule & Sendable]]

	/// Rules that don't provide start-character filters, sorted by priority (highest first).
	private let unfilteredRules: [any Rule & Sendable]

	/// Default parser with all standard rules
	static let `default` = InlineParser(rules: [
		InlineCodeRule(),
		EmphasisRule(),
		LinkRule(),
		URLRule(),
		TagRule(),
		PageLinkRule(),
		BlockRefRule(),
		HighlightRule(),
	])

	/// Parser for link text (formatting only, no references or nested links)
	static let formattingOnly = InlineParser(rules: [
		InlineCodeRule(),
		EmphasisRule(),
		HighlightRule(),
	])

	/// Parser for reference extraction only (no formatting rules)
	static let referencesOnly = InlineParser(rules: [
		InlineCodeRule(), // skip refs inside code
		LinkRule(), // skip refs inside markdown links
		URLRule(), // skip refs inside URLs (e.g. #fragment)
		TagRule(),
		PageLinkRule(),
		BlockRefRule(),
	])

	init(rules: [any Rule & Sendable]) {
		let sortedRules = rules.sorted { $0.priority > $1.priority }
		var rulesByStartingCharacter: [Character: [any Rule & Sendable]] = [:]
		var unfilteredRules: [any Rule & Sendable] = []

		for rule in sortedRules {
			guard let startingCharacters = rule.startingCharacters else {
				unfilteredRules.append(rule)
				continue
			}

			for character in startingCharacters {
				rulesByStartingCharacter[character, default: []].append(rule)
			}
		}

		self.rulesByStartingCharacter = rulesByStartingCharacter
		self.unfilteredRules = unfilteredRules
	}

	/// Parse text into a list of InlineSpan nodes
	func parse(_ text: String) -> [InlineSpan] {
		guard !text.isEmpty else { return [] }

		var spans: [InlineSpan] = []
		var index = text.startIndex
		var plainTextStart = text.startIndex

		while index < text.endIndex {
			let currentCharacter = text[index]
			let rulesToTry: [any Rule & Sendable]

			if unfilteredRules.isEmpty {
				rulesToTry = rulesByStartingCharacter[currentCharacter] ?? []
			} else {
				rulesToTry = candidateRules(for: currentCharacter)
			}

			// Try each rule in priority order
			var matched = false
			for rule in rulesToTry {
				if let span = rule.match(in: text, at: index, using: self) {
					// Emit accumulated plain text before this span
					if plainTextStart < index {
						spans.append(InlineSpan(
							kind: .text,
							range: plainTextStart..<index,
							content: String(text[plainTextStart..<index])
						))
					}
					spans.append(span)
					index = span.range.upperBound
					plainTextStart = index
					matched = true
					break
				}
			}
			if !matched {
				index = text.index(after: index)
			}
		}

		// Emit trailing plain text
		if plainTextStart < text.endIndex {
			spans.append(InlineSpan(
				kind: .text,
				range: plainTextStart..<text.endIndex,
				content: String(text[plainTextStart..<text.endIndex])
			))
		}

		return spans
	}

	/// Merge filtered and unfiltered rules while preserving global priority order.
	private func candidateRules(for character: Character) -> [any Rule & Sendable] {
		let filteredRules = rulesByStartingCharacter[character] ?? []

		guard !unfilteredRules.isEmpty else { return filteredRules }
		guard !filteredRules.isEmpty else { return unfilteredRules }

		var mergedRules: [any Rule & Sendable] = []
		mergedRules.reserveCapacity(filteredRules.count + unfilteredRules.count)

		var filteredIndex = 0
		var unfilteredIndex = 0

		while filteredIndex < filteredRules.count, unfilteredIndex < unfilteredRules.count {
			if filteredRules[filteredIndex].priority >= unfilteredRules[unfilteredIndex].priority {
				mergedRules.append(filteredRules[filteredIndex])
				filteredIndex += 1
			} else {
				mergedRules.append(unfilteredRules[unfilteredIndex])
				unfilteredIndex += 1
			}
		}

		if filteredIndex < filteredRules.count {
			mergedRules.append(contentsOf: filteredRules[filteredIndex...])
		}
		if unfilteredIndex < unfilteredRules.count {
			mergedRules.append(contentsOf: unfilteredRules[unfilteredIndex...])
		}

		return mergedRules
	}

	/// Extract all references from text (flattens nested spans)
	func extractReferences(from text: String) -> [InlineSpan] {
		let spans = parse(text)
		return collectReferences(from: spans, parentContent: text, in: text, contentStartOffset: 0)
	}

	/// Recursively collect reference spans from a span tree, rebasing ranges to the original text
	private func collectReferences(from spans: [InlineSpan], parentContent: String, in originalText: String, contentStartOffset: Int) -> [InlineSpan] {
		var refs: [InlineSpan] = []
		for span in spans {
			if span.kind.isReference {
				let lowerOffset = contentStartOffset + parentContent.distance(from: parentContent.startIndex, to: span.range.lowerBound)
				let upperOffset = contentStartOffset + parentContent.distance(from: parentContent.startIndex, to: span.range.upperBound)
				let newLower = originalText.index(originalText.startIndex, offsetBy: lowerOffset)
				let newUpper = originalText.index(originalText.startIndex, offsetBy: upperOffset)

				refs.append(InlineSpan(
					kind: span.kind,
					range: newLower..<newUpper,
					content: span.content,
					children: span.children
				))
			}

			// Extract reference from internal-destination markdown links
			if case let .link(url, _) = span.kind, url.scheme == "lattice" {
				if let refSpan = synthesizeReference(from: span, parentContent: parentContent, originalText: originalText, contentStartOffset: contentStartOffset) {
					refs.append(refSpan)
				}
			}

			// Don't recurse into references, but do recurse into formatting spans
			if !span.kind.isReference, !span.children.isEmpty {
				let spanStartInContent = parentContent.distance(from: parentContent.startIndex, to: span.range.lowerBound)
				let rawLength = parentContent.distance(from: span.range.lowerBound, to: span.range.upperBound)

				// Compute opening delimiter length to find where content starts
				let openingDelimiterLength: Int
				switch span.kind {
					case .bold, .italic, .highlight: openingDelimiterLength = (rawLength - span.content.count) / 2
					case .link, .code: openingDelimiterLength = 1
					default: openingDelimiterLength = 0
				}

				let childContentStartOffset = contentStartOffset + spanStartInContent + openingDelimiterLength

				refs.append(contentsOf: collectReferences(
					from: span.children,
					parentContent: span.content,
					in: originalText,
					contentStartOffset: childContentStartOffset
				))
			}
		}
		return refs
	}
}

// MARK: - Internal Reference Synthesis

private extension InlineParser {
	/// Synthesize a reference span from an internal-destination markdown link.
	///
	/// The reference range covers just the destination syntax (e.g. `[[page]]`) in the original text.
	func synthesizeReference(from span: InlineSpan, parentContent: String, originalText: String, contentStartOffset: Int) -> InlineSpan? {
		// Compute the range of the destination syntax in the original text.
		// The span raw text is: [linkText](destination)
		let spanStartOffset = contentStartOffset + parentContent.distance(from: parentContent.startIndex, to: span.range.lowerBound)
		let spanEndOffset = contentStartOffset + parentContent.distance(from: parentContent.startIndex, to: span.range.upperBound)
		let destStart = spanStartOffset + 1 + span.content.count + 2 // skip [content](
		let destEnd = spanEndOffset - 1 // before )

		guard destStart < destEnd, destEnd <= originalText.count else { return nil }

		let destLower = originalText.index(originalText.startIndex, offsetBy: destStart)
		let destUpper = originalText.index(originalText.startIndex, offsetBy: destEnd)

		let destination = String(originalText[destLower..<destUpper])
		guard let (kind, target) = InlineSpan.Kind.fromRefDestination(destination) else { return nil }

		return InlineSpan(kind: kind, range: destLower..<destUpper, content: target, children: [])
	}
}

extension InlineParser.Rule {
	var startingCharacters: Set<Character>? {
		nil
	}
}
