import SwiftUI
import SQLiteData
import Dependencies

@MainActor @Observable
final class ReferenceSuggestions {
	struct Context: Equatable {
		enum Kind: Equatable {
			case pageLink, tagSimple, tagBracketed
		}

		let kind: Kind
		let query: String
		let fullText: String
		let cursorOffset: Int
		let queryRange: NSRange
		let tokenRange: NSRange
	}

	@Selection
	struct Item: Equatable {
		let title: String
		let isSyntheticNewPage: Bool

		static func matchingPages(for query: String, limit: Int) -> Select<Item, Page, Void> {
			Page
				.where { $0.title.contains(query) }
				.order { $0.updatedAt.desc() }
				.limit(limit)
				.select {
					Item.Columns(
						title: $0.title,
						isSyntheticNewPage: #bind(false)
					)
				}
		}
	}

	enum Command {
		case moveUp, moveDown, accept, dismiss
	}

	enum Trigger {
		case explicitTrigger, textEdited, selectionChanged
	}

	nonisolated static let coordinateSpace = "ReferenceSuggestionsCoordinateSpace"

	var context: Context?
	var highlightedIndex = 0
	var activeBlockID: Block.ID?
	var anchorRect: CGRect = .zero
	var shouldScrollToHighlighted = false

	@ObservationIgnored @Dependency(\.platform) private var platform
	@ObservationIgnored @FetchAll private var fetchedSuggestions: [Item]
	@ObservationIgnored @Dependency(\.blockCoordinator) private var blockCoordinator

	private let maximumSuggestionCount = 30
	private var loadTask: Task<Void, any Error>?
	private var activeOnTextChanged: ((String) -> Void)?

	var isQueryEmpty: Bool {
		guard let context else { return true }
		return context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	var suggestions: [Item] {
		guard let context else { return [] }
		guard !context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

		if fetchedSuggestions.isEmpty {
			return [Item(title: context.query, isSyntheticNewPage: true)]
		}

		return fetchedSuggestions
	}

	func handleContextChange(
		for blockId: Block.ID?,
		context: ReferenceSuggestions.Context?,
		caretRect: CGRect?,
		onTextChanged: @escaping (String) -> Void
	) {
		guard let context else {
			guard activeBlockID == blockId else { return }
			return dismiss()
		}

		let isNewActiveBlock = activeBlockID != blockId
		let oldQuery = isNewActiveBlock ? nil : self.context?.query
		activeBlockID = blockId
		activeOnTextChanged = onTextChanged
		self.context = context
		if let caretRect { anchorRect = caretRect }

		if isNewActiveBlock || oldQuery != context.query {
			highlightedIndex = 0
			shouldScrollToHighlighted = false
			loadSuggestions(for: context.query)
		}
	}

	func updateAnchor(for blockId: Block.ID?, caretRect: CGRect?) {
		guard activeBlockID == blockId, context != nil, let caretRect else { return }
		anchorRect = caretRect
	}

	func offsetAnchor(for blockId: Block.ID?, by delta: CGSize) {
		guard activeBlockID == blockId, context != nil else { return }
		guard delta.width != 0 || delta.height != 0 else { return }
		anchorRect = anchorRect.offsetBy(dx: delta.width, dy: delta.height)
	}

	func handleCommand(_ command: Command, from blockId: Block.ID?) -> Bool {
		switch command {
			case .moveUp:
				guard platform.hasKeyboard, context != nil, activeBlockID == blockId, !suggestions.isEmpty else { return false }
				moveHighlightedSuggestion(delta: -1)
				return true

			case .moveDown:
				guard platform.hasKeyboard, context != nil, activeBlockID == blockId, !suggestions.isEmpty else { return false }
				moveHighlightedSuggestion(delta: 1)
				return true

			case .accept:
				guard activeBlockID == blockId else { return false }
				guard !suggestions.isEmpty else { return false }
				let index = clamp(highlightedIndex, to: 0...(suggestions.count - 1))
				return acceptSuggestion(withTitle: suggestions[index].title)

			case .dismiss:
				guard context != nil, activeBlockID == blockId else { return false }
				dismiss()
				return true
		}
	}

	@discardableResult
	func acceptSuggestion(withTitle title: String) -> Bool {
		guard let context else { return false }
		guard let activeOnTextChanged else { return false }
		let replacement = replacingReferenceSuggestion(in: context.fullText, context: context, with: title)

		activeOnTextChanged(replacement.text)

		if let activeBlockID {
			blockCoordinator.request(
				for: activeBlockID,
				at: replacement.cursorOffsetAfterToken,
				expectsNewText: true,
				startingInMode: .raw
			)
		}

		dismiss()
		return true
	}

	func endEditing(for blockId: Block.ID?) {
		guard activeBlockID == blockId else { return }
		dismiss()
	}

	func dismiss() {
		loadTask?.cancel()
		loadTask = nil
		context = nil
		activeBlockID = nil
		activeOnTextChanged = nil
		highlightedIndex = 0
		shouldScrollToHighlighted = false
	}

	private func replacingReferenceSuggestion(
		in text: String, context: ReferenceSuggestions.Context, with suggestionTitle: String
	) -> (text: String, cursorOffsetAfterToken: Int) {
		let replacementToken = switch context.kind {
			case .pageLink:
				"[[\(suggestionTitle)]]"
			case .tagSimple, .tagBracketed:
				TagSyntax.makeTagReference(for: suggestionTitle)
		}

		let updatedText = (text as NSString).replacingCharacters(in: context.tokenRange, with: replacementToken)
		let cursorOffsetAfterToken = context.tokenRange.location + replacementToken.utf16Length
		return (updatedText, cursorOffsetAfterToken)
	}

	private func moveHighlightedSuggestion(delta: Int) {
		guard !suggestions.isEmpty else { return }

		highlightedIndex = clamp(highlightedIndex + delta, to: 0...(suggestions.count - 1))
		shouldScrollToHighlighted = true
	}

	private func loadSuggestions(for query: String) {
		guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			loadTask?.cancel()
			loadTask = nil
			highlightedIndex = 0
			shouldScrollToHighlighted = false
			return
		}

		loadTask?.cancel()
		loadTask = Task {
			_ = await withErrorReporting {
				try await $fetchedSuggestions.load(
					Item.matchingPages(for: query, limit: maximumSuggestionCount),
					animation: .default
				)
			}
		}
	}
}

// MARK: - Reference Context

extension ReferenceSuggestions.Context {
	init?(in text: String, cursorOffset: Int) {
		let nsText = text as NSString
		let safeCursorOffset = clamp(cursorOffset, to: 0...nsText.length)

		if let context = Self.forDoubleBracketReference(in: nsText, cursorOffset: safeCursorOffset) {
			self = context
			return
		}

		if let context = Self.forSimpleTag(in: nsText, cursorOffset: safeCursorOffset) {
			self = context
			return
		}

		return nil
	}

	private static func forSimpleTag(in text: NSString, cursorOffset: Int) -> Self? {
		guard cursorOffset > 0 else { return nil }

		let hashLocation = text.range(of: "#", options: .backwards, range: NSRange(location: 0, length: cursorOffset)).location
		guard hashLocation != NSNotFound else { return nil }

		let queryStart = hashLocation + 1
		guard !text.hasPrefix("[[", at: queryStart) else { return nil }
		let querySearchRange = NSRange(location: queryStart, length: text.length - queryStart)
		let firstInvalidLocation = text.rangeOfCharacter(
			from: TagSyntax.simpleAllowedScalars.inverted,
			options: [],
			range: querySearchRange
		).location
		let tokenEnd = firstInvalidLocation == NSNotFound ? text.length : firstInvalidLocation
		guard (queryStart...tokenEnd).contains(cursorOffset) else { return nil }

		let queryRange = NSRange(location: queryStart, length: tokenEnd - queryStart)
		guard queryRange.length > 0 else { return nil }
		return makeContext(
			kind: .tagSimple,
			in: text,
			cursorOffset: cursorOffset,
			queryRange: queryRange,
			tokenStart: hashLocation,
			tokenEnd: tokenEnd
		)
	}

	private static func forDoubleBracketReference(in text: NSString, cursorOffset: Int) -> Self? {
		var searchEnd = cursorOffset
		while searchEnd > 0 {
			let openRange = text.range(of: "[[", options: .backwards, range: NSRange(location: 0, length: searchEnd))
			guard openRange.location != NSNotFound else { return nil }

			let queryStart = openRange.location + openRange.length
			let closeSearchRange = NSRange(location: queryStart, length: text.length - queryStart)
			let closeRange = text.range(of: "]]", options: [], range: closeSearchRange)
			guard closeRange.location != NSNotFound else { return nil }

			if cursorOffset < queryStart || cursorOffset > closeRange.location {
				searchEnd = openRange.location
				continue
			}

			let isBracketedTag = text.hasCharacter("#", at: openRange.location - 1)
			let queryRange = NSRange(location: queryStart, length: closeRange.location - queryStart)
			let tokenStart = isBracketedTag ? (openRange.location - 1) : openRange.location
			return makeContext(
				kind: isBracketedTag ? .tagBracketed : .pageLink,
				in: text,
				cursorOffset: cursorOffset,
				queryRange: queryRange,
				tokenStart: tokenStart,
				tokenEnd: closeRange.location + closeRange.length
			)
		}

		return nil
	}

	private static func makeContext(
		kind: Kind,
		in text: NSString,
		cursorOffset: Int,
		queryRange: NSRange,
		tokenStart: Int,
		tokenEnd: Int
	) -> Self {
		Self(
			kind: kind,
			query: text.substring(with: queryRange),
			fullText: text as String,
			cursorOffset: cursorOffset,
			queryRange: queryRange,
			tokenRange: NSRange(location: tokenStart, length: tokenEnd - tokenStart)
		)
	}
}

// MARK: - Dependency Setup

extension ReferenceSuggestions: DependencyKey {
	static var liveValue = ReferenceSuggestions()
}

extension DependencyValues {
	var referenceSuggestionsCoordinator: ReferenceSuggestions {
		get { self[ReferenceSuggestions.self] }
		set { self[ReferenceSuggestions.self] = newValue }
	}
}
