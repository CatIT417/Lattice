#if os(macOS)
import AppKit
import SwiftUI
import Dependencies

extension NSTextView {
	// TODO: Figure out if this is still needed
	func setAttributedText(_ attributedString: NSAttributedString) {
		let savedDelegate = delegate
		delegate = nil
		textStorage?.setAttributedString(attributedString)
		delegate = savedDelegate
	}
}

struct EditableTextView: NSViewRepresentable {
	let blockId: Block.ID?
	let text: String
	let alignment: Block.TextAlignment
	let ctFont: CTFont
	let onLinkClicked: (URL) -> Void
	let handleAction: (EditableText.Action) -> Bool
	let onReferenceSuggestionCommand: (ReferenceSuggestions.Command) -> Bool
	let onReferenceSuggestionContextChange: (ReferenceSuggestions.Context?, CGRect?) -> Void

	@Dependency(\.blockCoordinator) var blockCoordinator

	private var nsFont: NSFont {
		ctFont as NSFont
	}

	func makeNSView(context: Context) -> AutosizingTextView {
		let textView = AutosizingTextView(usingTextLayoutManager: false)

		textView.font = nsFont
		textView.isEditable = true
		textView.isRichText = false
		textView.isSelectable = true
		textView.importsGraphics = false
		textView.drawsBackground = false
		textView.textContainerInset = .zero
		textView.delegate = context.coordinator
		context.coordinator.textView = textView
		textView.alignment = NSTextAlignment(alignment)
		textView.isAutomaticLinkDetectionEnabled = false
		textView.isAutomaticTextReplacementEnabled = true
		textView.isAutomaticDashSubstitutionEnabled = true
		textView.isAutomaticQuoteSubstitutionEnabled = true
		textView.isAutomaticSpellingCorrectionEnabled = true
		textView.typingAttributes = [.font: nsFont, .foregroundColor: NSColor.labelColor]
		textView.linkTextAttributes = [.cursor: NSCursor.pointingHand, .foregroundColor: NSColor.systemBlue]

		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.textContainer?.lineFragmentPadding = 0
		textView.textContainer?.widthTracksTextView = false
		textView.textContainer?.heightTracksTextView = false
		textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

		textView.setContentHuggingPriority(.required, for: .vertical)
		textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textView.setContentCompressionResistancePriority(.required, for: .vertical)
		textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		context.coordinator.setText(blockCoordinator.modeFor(blockId: blockId) ?? .rendered, text: text, textView: textView)

		return textView
	}

	func updateNSView(_ textView: AutosizingTextView, context: Context) {
		context.coordinator.parent = self

		if context.coordinator.lastKnownFont != nsFont {
			context.coordinator.lastKnownFont = nsFont

			let selectedRange = textView.selectedRange()
			context.coordinator.setText(
				context.coordinator.isEditing ? .raw : .rendered,
				text: context.coordinator.isEditing ? textView.attributedString().string : context.coordinator.lastKnownText,
				textView: textView
			)
			textView.setSelectedRange(selectedRange)
		}

		let alignment = NSTextAlignment(alignment)
		if textView.alignment != alignment { textView.alignment = alignment }

		if blockCoordinator.shouldFocus(blockId: blockId), textView.window?.firstResponder != textView {
			let placement = blockCoordinator.cursorPlacementFor(blockId: blockId)

			// View might not be in window yet (e.g., newly created from PlaceholderBlock).
			// Only clear focus after successfully becoming first responder.
			DispatchQueue.main.async { [weak blockCoordinator] in
				guard let window = textView.window else { return }
				window.makeFirstResponder(textView)

				switch placement {
					case let .offset(position): context.coordinator.moveCursorTo(offset: position, textView: textView)
					case let .visualX(x, edge): context.coordinator.moveCursorToVisualX(x, edge: edge, textView: textView)
					case nil: break
				}

				blockCoordinator?.clearFocus(for: self.blockId)
			}
		}

		if context.coordinator.lastKnownText != text, blockCoordinator.expectsNewText(for: blockId) || !context.coordinator.isEditing {
			context.coordinator.lastKnownText = text
			context.coordinator.setText(blockCoordinator.modeFor(blockId: blockId) ?? .rendered, text: text, textView: textView)
			if let cursorPosition = blockCoordinator.cursorPositionFor(blockId: blockId) {
				context.coordinator.moveCursorTo(offset: cursorPosition, textView: textView)
			}
			blockCoordinator.textReceived(for: blockId)
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView: AutosizingTextView, context _: Context) -> CGSize? {
		let width = proposal.width ?? 300

		nsView.proposedWidth = width

		guard let textContainer = nsView.textContainer, let layoutManager = nsView.layoutManager else {
			return nil
		}

		textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
		layoutManager.ensureLayout(for: textContainer)

		let usedRect = layoutManager.usedRect(for: textContainer)
		return CGSize(width: width, height: max(usedRect.height, 22))
	}

	static func dismantleNSView(_ nsView: AutosizingTextView, coordinator: Coordinator) {
		guard coordinator.isEditing else { return }

		if coordinator.parent.blockCoordinator.shouldFocus(blockId: coordinator.parent.blockId) {
			coordinator.saveIfEditing()
			coordinator.parent.blockCoordinator.editingEnded(for: coordinator.parent.blockId)
		} else {
			nsView.window?.makeFirstResponder(nil)
		}
	}
}

extension EditableTextView {
	@MainActor final class Coordinator: NSObject {
		var parent: EditableTextView
		weak var textView: NSTextView?

		var isEditing = false
		var lastKnownText: String
		var lastKnownFont: NSFont
		var indexMapping: AttributedStringResult.IndexMapping?
		var pendingFaviconURLs: Set<URL> = []
		var isReferenceSuggestionSessionActive = false
		var activateSuggestionsOnNextTextChange = false

		init(parent: EditableTextView) {
			self.parent = parent
			lastKnownText = parent.text
			lastKnownFont = parent.nsFont
			super.init()

			NotificationCenter.default.addObserver(
				self,
				selector: #selector(saveIfEditing),
				name: NSApplication.didResignActiveNotification,
				object: nil
			)
		}

		@objc func saveIfEditing() {
			guard isEditing, let textView else { return }
			let newText = textView.attributedString().string
			if newText != parent.text {
				_ = parent.handleAction(.textChanged(newText))
			}
			lastKnownText = newText
		}

		func setText(_ mode: BlockCoordinator.RenderMode, text: String, textView: NSTextView) {
			switch mode {
				case .raw:
					pendingFaviconURLs.removeAll()
					textView.setAttributedText(NSAttributedString(string: text, attributes: [
						.font: parent.nsFont,
						.foregroundColor: NSColor.labelColor,
					]))
				case .rendered:
					let result = buildAttributedString(from: text.strippingTodoPrefix(), font: parent.nsFont, rawStartOffset: text.todoPrefixUTF16Length, faviconProvider: FaviconLoader.image)
					indexMapping = result.indexMapping
					textView.setAttributedText(result.attributedString)

					let newURLs = result.uncachedFaviconURLs.subtracting(pendingFaviconURLs)
					pendingFaviconURLs.formUnion(newURLs)
					for faviconURL in newURLs {
						FaviconLoader.ensureLoaded(faviconURL: faviconURL, onSuccess: { [weak self] in
							guard let self else { return }
							self.pendingFaviconURLs.remove(faviconURL)
							guard !self.isEditing else { return }
							self.setText(.rendered, text: self.lastKnownText, textView: textView)
						}, onFailure: { [weak self] in
							self?.pendingFaviconURLs.remove(faviconURL)
						})
					}
			}

			textView.invalidateIntrinsicContentSize()
		}

		func moveCursorTo(offset: Int, textView: NSTextView) {
			let safeOffset = clamp(offset, to: 0 ... textView.string.utf16Length)
			textView.setSelectedRange(NSRange(location: safeOffset, length: 0))
		}

		func updateReferenceSuggestions(textView: NSTextView, trigger: ReferenceSuggestions.Trigger, activatingSession: Bool = false) {
			if activatingSession { isReferenceSuggestionSessionActive = true }
			if trigger == .selectionChanged, !isReferenceSuggestionSessionActive { return }

			let context = ReferenceSuggestions.Context(
				in: textView.attributedString().string,
				cursorOffset: textView.selectedRange().location
			)

			if trigger == .textEdited, context != nil {
				isReferenceSuggestionSessionActive = true
			}

			if let context, isReferenceSuggestionSessionActive {
				parent.onReferenceSuggestionContextChange(
					context,
					textView.caretRectForCurrentSelection(fallbackFont: parent.nsFont)
				)
			} else {
				if context == nil { isReferenceSuggestionSessionActive = false }
				parent.onReferenceSuggestionContextChange(nil, nil)
			}
		}

		func cursorXInWindow(textView: NSTextView) -> CGFloat {
			let cursorLocation = textView.selectedRange().location

			if cursorLocation == 0 { return -.infinity }
			if cursorLocation == textView.string.utf16Length { return .infinity }

			guard let layoutManager = textView.layoutManager else {
				return textView.convert(NSPoint(x: textView.textContainerOrigin.x, y: 0), to: nil).x
			}

			let textLength = textView.string.utf16Length
			guard textLength > 0 else {
				return textView.convert(NSPoint(x: textView.textContainerOrigin.x, y: 0), to: nil).x
			}

			let charIndex = min(cursorLocation, textLength - 1)
			let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)

			let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
			let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)

			var xInTextContainer = lineRect.origin.x + glyphLocation.x

			// If cursor is past the character (at end of text or after the glyph), add the glyph advance
			if cursorLocation > charIndex {
				let glyphRange = NSRange(location: glyphIndex, length: 1)
				let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!)
				xInTextContainer = glyphRect.maxX
			}

			let xInView = xInTextContainer + textView.textContainerOrigin.x
			return textView.convert(NSPoint(x: xInView, y: 0), to: nil).x
		}

		func moveCursorToVisualX(_ windowX: CGFloat, edge: BlockCoordinator.LineEdge, textView: NSTextView) {
			guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

			layoutManager.ensureLayout(for: textContainer)

			let textLength = textView.string.utf16Length
			guard textLength > 0 else {
				textView.setSelectedRange(NSRange(location: 0, length: 0))
				return
			}

			// Find the target line
			let targetGlyphIndex: Int = switch edge {
				case .first: 0
				case .last: layoutManager.glyphIndexForCharacter(at: textLength - 1)
			}

			let lineRect = layoutManager.lineFragmentRect(forGlyphAt: targetGlyphIndex, effectiveRange: nil)

			// Convert window X to text container coordinates
			let pointInView = textView.convert(NSPoint(x: windowX, y: 0), from: nil)
			let xInTextContainer = pointInView.x - textView.textContainerOrigin.x
			let pointInTextContainer = NSPoint(x: xInTextContainer, y: lineRect.midY)

			// Hit-test to find character
			var fraction: CGFloat = 0
			let glyphIndex = layoutManager.glyphIndex(for: pointInTextContainer, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
			var charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

			if fraction > 0.5 {
				charIndex = min(charIndex + 1, textLength)
			}

			textView.setSelectedRange(NSRange(location: charIndex, length: 0))
		}

		fileprivate func transitionToEditMode(textView: NSTextView) {
			isEditing = true
			parent.blockCoordinator.editingStarted(for: parent.blockId)

			let selectedRange = textView.selectedRange()

			setText(.raw, text: lastKnownText, textView: textView)

			textView.setSelectedRange(indexMapping?.transform(range: selectedRange, maxLength: parent.text.utf16Length) ?? selectedRange)

			if let pendingAction = parent.blockCoordinator.popAction(for: parent.blockId) {
				switch pendingAction {
					case .indent: _ = parent.handleAction(.indent(cursorPosition: textView.selectedRange().location, currentText: lastKnownText))
					case .outdent: _ = parent.handleAction(.outdent(cursorPosition: textView.selectedRange().location, currentText: lastKnownText))
				}
			}
		}

		fileprivate func deletionRequested(textView: NSTextView) {
			let currentText = textView.attributedString().string
			if parent.handleAction(.mergeIntoPrevious(appendingContent: currentText)) {
				textView.window?.makeFirstResponder(nil)
			}
		}

		fileprivate func newBlockRequested(textView: NSTextView, range: NSRange) {
			let currentText = textView.attributedString().string as NSString
			let newText = currentText.substring(to: range.location)
			let remainingText = currentText.substring(from: range.location + range.length)

			// Save the raw text before switching to rendered mode, otherwise
			// textDidEndEditing will read the rendered text (without [[...]] syntax)
			// and save that to the database, stripping the link formatting.
			_ = parent.handleAction(.textChanged(newText))
			lastKnownText = newText

			let createdNewBlock = parent.handleAction(.blockBreak(currentText: newText, remainingText: remainingText.isEmpty ? nil : remainingText))

			// Only switch to rendered mode if focus moved to a new block
			if createdNewBlock {
				isEditing = false
				setText(.rendered, text: newText, textView: textView)
			}
		}
	}
}

extension EditableTextView.Coordinator: NSTextViewDelegate {
	// MARK: - Focus/Edit Mode Transitions

	func textDidBeginEditing(_ notification: Notification) {
		guard let textView = notification.object as? NSTextView else { return }
	}

	func textViewDidChangeSelection(_ notification: Notification) {
		guard let textView = notification.object as? NSTextView else { return }

		guard isEditing else { return transitionToEditMode(textView: textView) }
		updateReferenceSuggestions(textView: textView, trigger: .selectionChanged)
	}

	func textDidEndEditing(_ notification: Notification) {
		guard let textView = notification.object as? NSTextView else { return }
		isReferenceSuggestionSessionActive = false
		activateSuggestionsOnNextTextChange = false
		parent.onReferenceSuggestionContextChange(nil, nil)

		guard isEditing else { return }
		isEditing = false
		parent.blockCoordinator.editingEnded(for: parent.blockId)

		let newText = textView.attributedString().string
		if newText != parent.text {
			_ = parent.handleAction(.textChanged(newText))
		}
		lastKnownText = newText

		setText(.rendered, text: newText, textView: textView)
	}

	// MARK: - Link Handling

	func textView(_ textView: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		if let url = link as? URL {
			parent.onLinkClicked(url)
			textView.window?.makeFirstResponder(nil)
			return true
		}

		return false
	}

	// MARK: - Text Changes

	func textDidChange(_ notification: Notification) {
		guard let textView = notification.object as? NSTextView else { return }
		textView.invalidateIntrinsicContentSize()
		updateReferenceSuggestions(
			textView: textView,
			trigger: .textEdited,
			activatingSession: activateSuggestionsOnNextTextChange
		)
		activateSuggestionsOnNextTextChange = false
	}

	func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
		guard let text else { return true }

		let currentText = textView.string as NSString
		if shouldActivateReferenceSuggestionSession(for: text, range: range, currentText: currentText) {
			activateSuggestionsOnNextTextChange = true
		}

		// set heading from "# ", "## ", or "### " prefix
		if let level = shouldSetHeading(for: text, range: range, currentText: currentText), parent.handleAction(.setHeading(level)) {
			setText(.raw, text: String(currentText.substring(from: range.location)), textView: textView)
			moveCursorTo(offset: 0, textView: textView)

			isReferenceSuggestionSessionActive = false
			activateSuggestionsOnNextTextChange = false
			parent.onReferenceSuggestionContextChange(nil, nil)

			return false
		}

		// move through character instead of inserting (for auto-closing characters)
		if shouldSkipClosingBracket(for: text, in: textView.string, at: range.location) {
			moveCursorTo(offset: range.location + 1, textView: textView)
			return false
		}

		// wrap selected text in markdown link when pasting a URL
		if range.length > 0, range.location + range.length <= (textView.string as NSString).length,
		   let markdownLink = markdownLinkFromPastedURL(for: text, selectedText: (textView.string as NSString).substring(with: range))
		{
			textView.insertText(markdownLink, replacementRange: range)
			moveCursorTo(offset: range.location + markdownLink.utf16.count, textView: textView)
			updateReferenceSuggestions(
				textView: textView,
				trigger: .textEdited,
				activatingSession: activateSuggestionsOnNextTextChange
			)
			activateSuggestionsOnNextTextChange = false
			return false
		}

		// wrap text with brackets instead of replacing it
		if range.length > 0, range.location + range.length <= (textView.string as NSString).length,
		   let wrappedText = wrapWithBrackets(for: text, selectedText: (textView.string as NSString).substring(with: range))
		{
			textView.insertText(wrappedText, replacementRange: range)

			textView.setSelectedRange(NSRange(location: range.location + 1, length: range.length))
			updateReferenceSuggestions(
				textView: textView,
				trigger: .textEdited,
				activatingSession: activateSuggestionsOnNextTextChange
			)
			activateSuggestionsOnNextTextChange = false
			return false
		}

		// auto-close brackets
		if let textToInsert = shouldAutoComplete(for: text) {
			textView.insertText(textToInsert, replacementRange: range)
			moveCursorTo(offset: range.location + 1, textView: textView)
			updateReferenceSuggestions(
				textView: textView,
				trigger: .textEdited,
				activatingSession: activateSuggestionsOnNextTextChange
			)
			activateSuggestionsOnNextTextChange = false
			return false
		}

		return true
	}

	// MARK: - Command Handling

	func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		// [esc] close suggestions panel
		if selector == #selector(NSResponder.cancelOperation(_:)), parent.onReferenceSuggestionCommand(.dismiss) {
			isReferenceSuggestionSessionActive = false
			return true
		}

		// [↑] previous suggestion
		if selector == #selector(NSResponder.moveUp(_:)), parent.onReferenceSuggestionCommand(.moveUp) {
			return true
		}

		// [↓] next suggestion
		if selector == #selector(NSResponder.moveDown(_:)), parent.onReferenceSuggestionCommand(.moveDown) {
			return true
		}

		// [⏎ | tab] accept suggestion
		if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)),
		   parent.onReferenceSuggestionCommand(.accept)
		{
			isReferenceSuggestionSessionActive = false
			return true
		}

		// [esc] unfocus block
		if selector == #selector(NSResponder.cancelOperation(_:)) {
			textView.window?.makeFirstResponder(nil)
			return true
		}

		// [⏎] create new block
		if selector == #selector(NSResponder.insertNewline(_:)) {
			newBlockRequested(textView: textView, range: textView.selectedRange())
			return true
		}

		// [⌫] delete block
		if selector == #selector(NSResponder.deleteBackward(_:)) {
			let range = textView.selectedRange()

			if range.location == 0, range.length == 0 {
				deletionRequested(textView: textView)
				return true
			}

			if range.length == 0, let rangeToDelete = shouldAutoDelete(in: textView.string, at: range.location) {
				textView.insertText("", replacementRange: rangeToDelete)
				moveCursorTo(offset: rangeToDelete.location, textView: textView)
				return true
			}
		}

		// [↑] move to previous block
		if selector == #selector(NSResponder.moveUp(_:)), textView.isCursorOnFirstLine(), parent.handleAction(.moveCursorUp(visualX: cursorXInWindow(textView: textView))) {
			return true
		}

		// [↓] move to next block
		if selector == #selector(NSResponder.moveDown(_:)), textView.isCursorOnLastLine(), parent.handleAction(.moveCursorDown(visualX: cursorXInWindow(textView: textView))) {
			return true
		}

		// [tab] indent block
		if selector == #selector(NSResponder.insertTab(_:)) {
			if parent.blockCoordinator.shouldQueueActions(blockId: parent.blockId) { parent.blockCoordinator.queueAction(.indent) }
			else { _ = parent.handleAction(.indent(cursorPosition: textView.selectedRange().location, currentText: textView.attributedString().string)) }

			return true
		}

		// [⇧ + tab] outdent block
		if selector == #selector(NSResponder.insertBacktab(_:)) {
			if parent.blockCoordinator.shouldQueueActions(blockId: parent.blockId) { parent.blockCoordinator.queueAction(.outdent) }
			else { _ = parent.handleAction(.outdent(cursorPosition: textView.selectedRange().location, currentText: textView.attributedString().string)) }

			return true
		}

		return false
	}
}

final class AutosizingTextView: NSTextView {
	var proposedWidth: CGFloat = 0

	override var intrinsicContentSize: NSSize {
		guard let textContainer = textContainer, let layoutManager = layoutManager else {
			return super.intrinsicContentSize
		}

		let width = proposedWidth > 0 ? proposedWidth : (bounds.width > 0 ? bounds.width : 300)
		textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
		layoutManager.ensureLayout(for: textContainer)

		let usedRect = layoutManager.usedRect(for: textContainer)
		return NSSize(width: NSView.noIntrinsicMetric, height: max(usedRect.height, 22))
	}
}
#endif
