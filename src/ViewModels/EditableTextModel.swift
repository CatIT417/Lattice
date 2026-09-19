import SwiftUI
import Dependencies
import DebugSnapshots

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor @Observable @DebugSnapshot
final class EditableTextModel {
	/// Whether the model is editing raw text (separate from native focus)
	private(set) var isEditing = false

	/// Raw source retained for rendering and restoring editing. Native edits can be newer.
	private(set) var sourceText = ""

	/// Whether an iOS link press must cancel the next attempt to start editing.
	private(set) var linkWasTapped = false

	/// Whether iOS is waiting to switch from rendered text to raw text.
	private(set) var isEditTransitionPending = false

	/// Favicon URLs tracked to prevent duplicate requests while text is rendered.
	private(set) var pendingFaviconURLs: Set<URL> = []

	/// Whether selection changes can update the current reference suggestions.
	private(set) var isReferenceSuggestionSessionActive = false

	/// The block shown by this editor, if one is assigned.
	@ObservationIgnored private var blockId: Block.ID?

	/// Opens a link through the parent view.
	@ObservationIgnored private var onLinkClicked: (URL) -> Void = { _ in }

	/// Native view that holds the text and selection.
	@ObservationIgnored @DebugSnapshotIgnored weak var textView: PlatformTextView?

	/// Converts rendered text positions to raw text positions when editing starts.
	@ObservationIgnored private var renderedToRawMapping: AttributedStringResult.IndexMapping?

	/// Font used for raw and rendered text.
	@ObservationIgnored private var font: PlatformFont = .preferredFont(forTextStyle: .body)

	/// Sends block actions to the parent view. Each action defines the meaning of its Boolean result.
	@ObservationIgnored private var handleAction: (EditableText.Action) -> Bool = { _ in false }

	/// Sends a suggestion command to the parent. Returns true if the command was handled.
	@ObservationIgnored private var onReferenceSuggestionCommand: (ReferenceSuggestions.Command) -> Bool = { _ in false }

	/// Sends the suggestion context and caret rectangle to the parent. A nil context ends the session.
	@ObservationIgnored private var onReferenceSuggestionContextChange: (ReferenceSuggestions.Context?, CGRect?) -> Void = { _, _ in }

	/// Shares focus requests and pending block actions between editors.
	@ObservationIgnored @Dependency(\.blockCoordinator) private var blockCoordinator

	#if os(iOS)
	/// Tracks selected blocks on iOS. Used to prevent editing during block selection.
	@ObservationIgnored @Dependency(\.blockSelectionCoordinator) private var selectionCoordinator
	#endif

	/// Text in the native view.
	///
	/// Contains raw syntax during the editing phase, and rendered text otherwise.
	@DebugSnapshotTracked var displayedText: String {
		#if os(iOS)
		textView?.text ?? ""
		#else
		textView?.string ?? ""
		#endif
	}

	/// Selection in the native text, in UTF-16 code units. Length of 0 indicates the cursor position.
	@DebugSnapshotTracked var selectedRange: NSRange {
		get {
			#if os(iOS)
			textView?.selectedRange ?? NSRange(location: 0, length: 0)
			#else
			textView?.selectedRange() ?? NSRange(location: 0, length: 0)
			#endif
		}
		set {
			#if os(iOS)
			textView?.selectedRange = newValue
			#else
			textView?.setSelectedRange(newValue)
			#endif
		}
	}

	/// Whether the native view is the first responder and has keyboard focus.
	var isFirstResponder: Bool {
		#if os(iOS)
		textView?.isFirstResponder ?? false
		#else
		guard let textView else { return false }
		return textView.window?.firstResponder == textView
		#endif
	}

	// MARK: - View Updates

	/// Updates parent inputs, handles pending focus, and refreshes the native text.
	///
	/// Keeps an active draft unless the block coordinator expects replacement text.
	///
	/// - Parameter blockId: Block represented by this editor, or nil if no block is assigned.
	/// - Parameter originalText: Latest saved text from the parent.
	/// - Parameter font: Font for raw and rendered text.
	/// - Parameter handleAction: Receives block actions. Each action defines the meaning of its Boolean result.
	/// - Parameter onLinkClicked: Opens a link through the parent.
	/// - Parameter onReferenceSuggestionCommand: Handles suggestion commands. Returns true if a command was handled.
	/// - Parameter onReferenceSuggestionContextChange: Receives the context and caret rectangle in native view coordinates. A nil context ends suggestions.
	func update(
		blockId: Block.ID?, originalText: String, font: PlatformFont,
		handleAction: @escaping (EditableText.Action) -> Bool,
		onLinkClicked: @escaping (URL) -> Void,
		onReferenceSuggestionCommand: @escaping (ReferenceSuggestions.Command) -> Bool,
		onReferenceSuggestionContextChange: @escaping (ReferenceSuggestions.Context?, CGRect?) -> Void
	) {
		self.blockId = blockId
		self.handleAction = handleAction
		self.onLinkClicked = onLinkClicked
		self.onReferenceSuggestionCommand = onReferenceSuggestionCommand
		self.onReferenceSuggestionContextChange = onReferenceSuggestionContextChange
		guard textView != nil else {
			sourceText = originalText
			self.font = font
			return
		}

		// re-render if font changed
		if self.font != font {
			self.font = font
			let range = selectedRange
			setText(isEditing ? .raw : .rendered, text: isEditing ? displayedText : sourceText)
			selectedRange = range
		}

		// Schedule focus before textReceived can clear the pending request and cursor placement.
		focusRequested()
		if sourceText != originalText, blockCoordinator.expectsNewText(for: blockId) || !isEditing {
			sourceText = originalText
			setText(blockCoordinator.modeFor(blockId: blockId) ?? .rendered, text: originalText)
			if let offset = blockCoordinator.cursorPositionFor(blockId: blockId) {
				moveCursor(to: offset)
			}
			blockCoordinator.textReceived(for: blockId)
		}
	}

	/// Attaches the native view and displays the retained source text.
	func textViewAttached(_ textView: PlatformTextView) {
		self.textView = textView
		setText(blockCoordinator.modeFor(blockId: blockId) ?? .rendered, text: sourceText)
	}

	// MARK: - Focus and Editing

	/// Schedules native focus and cursor placement for a pending block request.
	func focusRequested() {
		guard let textView, blockCoordinator.shouldFocus(blockId: blockId), !isFirstResponder else { return }

		let placement = blockCoordinator.cursorPlacementFor(blockId: blockId)

		// Becoming the first responder synchronously triggers an AttributeGraph cycle
		// when calling BlockCoordinator.request in ParagraphView.moveCursorTo.
		// View might not be in window yet (e.g., newly created from PlaceholderBlock).
		// Only clear focus after successfully becoming first responder.
		DispatchQueue.main.async { [weak self, weak textView] in
			guard let self, let textView, self.textView === textView else { return }

			// become first responder
			#if os(iOS)
			guard textView.becomeFirstResponder() else { return }
			#else
			guard let window = textView.window, window.makeFirstResponder(textView) else { return }
			#endif

			// restore cursor placement (if any)
			switch placement {
				case let .offset(offset): self.moveCursor(to: offset)
				case let .visualX(x, edge): self.moveCursorToVisualX(x, edge: edge, textView: textView)
				case nil: break
			}

			self.blockCoordinator.clearFocus(for: self.blockId)
		}
	}

	#if os(iOS)
	/// Starts an editing session after native editing begins.
	///
	/// Waits for cursor placement and prevents editing after a link press or during block selection.
	func editingBegan() {
		if linkWasTapped {
			linkWasTapped = false
			endNativeEditing()
			return
		}

		guard !isEditing, !selectionCoordinator.hasSelection else { return }
		isEditTransitionPending = true

		// If the user is tapping to place the cursor, `textViewDidChangeSelection` will transition
		// to edit mode. We wait a moment to see if that happens and manually transition if not.
		DispatchQueue.main.async { [weak self] in
			guard let self, self.isEditTransitionPending else { return }
			self.transitionToEditMode()
		}
	}
	#endif

	/// Starts raw editing when needed. Otherwise, updates the active suggestion session.
	func selectionChanged() {
		#if os(iOS)
		if isEditTransitionPending { return transitionToEditMode() }
		#else
		guard isEditing else { return transitionToEditMode() }
		#endif

		updateReferenceSuggestions(trigger: .selectionChanged)
	}

	/// Ends editing and suggestions, requests a save, and restores rendered text.
	func editingEnded() {
		#if os(iOS)
		isEditTransitionPending = false
		#endif

		endSuggestionSession()
		guard isEditing else { return }
		isEditing = false
		blockCoordinator.editingEnded(for: blockId)
		saveDraft()
		setText(.rendered, text: sourceText)
	}

	/// Save the draft but don't clear focus.
	func appResignedActive() {
		guard isEditing, textView != nil else { return }
		saveDraft()
	}

	/// Ends the model session and clears the native view reference.
	func textViewDetached() {
		#if os(macOS)
		if isEditing {
			if blockCoordinator.shouldFocus(blockId: blockId) {
				appResignedActive()
				blockCoordinator.editingEnded(for: blockId)
			} else {
				endNativeEditing()
			}
		}
		#else
		appResignedActive()
		if isEditing {
			blockCoordinator.editingEnded(for: blockId)
		}
		isEditTransitionPending = false
		linkWasTapped = false
		#endif

		isEditing = false
		endSuggestionSession()
		textView = nil
	}

	/// Asks the native view to give up keyboard focus.
	private func endNativeEditing() {
		#if os(iOS)
		textView?.resignFirstResponder()
		#else
		textView?.window?.makeFirstResponder(nil)
		#endif
	}

	/// Starts raw editing and converts the cursor or selection from rendered text positions.
	///
	/// On macOS, also applies any queued indent or outdent action.
	private func transitionToEditMode() {
		guard textView != nil else { return }

		isEditing = true
		#if os(iOS)
		isEditTransitionPending = false
		#endif

		blockCoordinator.editingStarted(for: blockId)
		let range = selectedRange
		setText(.raw, text: sourceText)

		#if os(iOS)
		moveCursor(to: renderedToRawMapping?.rawIndex(fromRendered: range.location) ?? range.location)
		#else
		selectedRange = renderedToRawMapping?.transform(range: range, maxLength: sourceText.utf16Length) ?? range
		if let action = blockCoordinator.popAction(for: blockId) {
			switch action {
				case .indent: indentButtonTapped()
				case .outdent: outdentButtonTapped()
			}
		}
		#endif
	}

	/// Requests a save and retains the draft as raw source. The parent skips unchanged text.
	private func saveDraft() {
		let draft = displayedText
		_ = handleAction(.saveDraft(draft))
		sourceText = draft
	}

	// MARK: - Keyboard Actions

	/// Accepts a suggestion, or requests a block break at the selection.
	///
	/// - Parameter range: Valid selection in raw text, in UTF-16 code units. Nil uses `selectedRange`.
	/// - Returns: Always true. Native Return handling must stop.
	@discardableResult func returnPressed(in range: NSRange? = nil) -> Bool {
		let range = range ?? selectedRange

		// [⏎] accept suggestion
		if acceptSuggestion() {
			return true
		}

		// [⏎] create new block
		let text = displayedText as NSString
		let first = text.substring(to: range.location)
		let remaining = text.substring(from: range.location + range.length)

		// Save the raw text before switching to rendered mode. Otherwise, the end-editing
		// callback can save the rendered text without the [[...]] link syntax.
		_ = handleAction(.saveDraft(first))
		sourceText = first

		// Only switch to rendered mode if focus moved to a new block
		let createdNewBlock = handleAction(.blockBreak(currentText: first, remainingText: remaining.isEmpty ? nil : remaining))
		if createdNewBlock {
			isEditing = false
			#if os(iOS)
			endNativeEditing()
			#endif
			setText(.rendered, text: first)
		}

		return true
	}

	/// Requests a block merge at the start, or deletes an empty bracket pair.
	///
	/// - Parameter range: Selection before deletion, in UTF-16 code units. Nil uses `selectedRange`.
	/// - Returns: True to stop native handling; false to allow native deletion.
	func backspacePressed(in range: NSRange? = nil) -> Bool {
		let range = range ?? selectedRange

		// [⌫] delete block
		if range.location == 0, range.length == 0 {
			if handleAction(.mergeIntoPrevious(appendingContent: displayedText)) {
				endNativeEditing()
			}
			return true
		}

		// [⌫] delete inside empty bracket pair
		if range.length == 0, let deletion = bracketPairDeletionRange(in: displayedText, at: range.location) {
			replaceText(in: deletion, with: "")
			moveCursor(to: deletion.location)
			return true
		}

		return false
	}

	/// Accepts a suggestion or requests an indent.
	///
	/// - Returns: Always true. Native Tab handling must stop.
	@discardableResult func tabPressed() -> Bool {
		// If there's an active suggestion, accept it. Otherwise, request an indent.
		if !acceptSuggestion() {
			indentButtonTapped()
		}

		return true
	}

	/// Requests an outdent.
	///
	/// - Returns: Always true. Native Shift-Tab handling must stop.
	@discardableResult
	func backtabPressed() -> Bool {
		// [⇧ + tab] outdent block
		outdentButtonTapped()
		return true
	}

	/// Dismisses suggestions, or ends native editing on macOS.
	///
	/// - Returns: True to stop native handling; false to allow it.
	func escapePressed() -> Bool {
		// [esc] close suggestions panel
		if onReferenceSuggestionCommand(.dismiss) {
			isReferenceSuggestionSessionActive = false
			return true
		}

		#if os(macOS)
		// [esc] unfocus block
		endNativeEditing()
		return true
		#else
		return false
		#endif
	}

	/// Selects the previous suggestion, or requests the previous block from the first visual line.
	///
	/// - Returns: True to stop native handling; false to allow it.
	func upArrowPressed() -> Bool {
		// [↑] previous suggestion
		if onReferenceSuggestionCommand(.moveUp) {
			return true
		}

		// [↑] move to previous block
		guard let textView, textView.isCursorOnFirstLine() else { return false }
		return handleAction(.moveCursorUp(visualX: cursorXInWindow(textView: textView)))
	}

	/// Selects the next suggestion, or requests the next block from the last visual line.
	///
	/// - Returns: True to stop native handling; false to allow it.
	func downArrowPressed() -> Bool {
		// [↓] next suggestion
		if onReferenceSuggestionCommand(.moveDown) {
			return true
		}

		// [↓] move to next block
		guard let textView, textView.isCursorOnLastLine() else { return false }
		return handleAction(.moveCursorDown(visualX: cursorXInWindow(textView: textView)))
	}

	// MARK: - Toolbar and Link Actions

	/// Requests an indent with the current draft and cursor position.
	/// On macOS, queues the action if another editor is waiting for focus.
	func indentButtonTapped() {
		#if os(macOS)
		if blockCoordinator.shouldQueueActions(blockId: blockId) {
			return blockCoordinator.queueAction(.indent)
		}
		#endif

		sourceText = displayedText
		_ = handleAction(.indent(cursorPosition: selectedRange.location, currentText: sourceText))
	}

	/// Requests an outdent with the current draft and cursor position.
	/// On macOS, queues the action if another editor is waiting for focus.
	func outdentButtonTapped() {
		#if os(macOS)
		if blockCoordinator.shouldQueueActions(blockId: blockId) {
			return blockCoordinator.queueAction(.outdent)
		}
		#endif

		sourceText = displayedText
		_ = handleAction(.outdent(cursorPosition: selectedRange.location, currentText: sourceText))
	}

	#if os(iOS)
	/// Requests a block move with the current draft and cursor position.
	///
	/// - Parameter delta: Use -1 to move up or 1 to move down.
	func moveBlockButtonTapped(delta: Int) {
		sourceText = displayedText
		_ = handleAction(.moveBlock(delta: delta, cursorPosition: selectedRange.location, currentText: sourceText))
	}

	/// Selects or deselects this block and provides haptic feedback.
	func blockSelected() {
		guard let blockId else { return }

		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		withAnimation(selectionCoordinator.animation) { selectionCoordinator.toggleSelection(on: blockId) }
	}

	/// Marks an iOS link press to prevent the next attempt to start editing.
	func linkPressed() {
		linkWasTapped = true
	}
	#endif

	/// Opens the supplied URL through the parent.
	///
	/// Ends native editing on macOS.
	func linkTapped(_ url: URL) {
		onLinkClicked(url)
		#if os(macOS)
		endNativeEditing()
		#endif
	}

	/// Changes to the next todo state and keeps the cursor relative to the content.
	///
	/// Applies only during editing.
	func todoButtonTapped() {
		guard isEditing else { return }

		let text = displayedText
		let state = text.todoState.next
		let offset = selectedRange.location
		let updated = text.withTodoState(state)

		_ = handleAction(.saveDraft(updated))
		sourceText = updated
		setText(.raw, text: updated)
		moveCursor(to: offset + (state?.prefixUTF16Length ?? 0) - text.todoPrefixUTF16Length)
	}

	/// Handles a photo button tap.
	func photoButtonTapped() {
		// TODO: Add photo handling
	}

	/// Wraps or unwraps the selection with `[[...]]` and updates reference suggestions.
	func bracketsButtonTapped() {
		let range = selectedRange
		let text = displayedText as NSString
		let inner = text.substring(with: range)

		if range.location >= 2, NSMaxRange(range) + 2 <= text.length,
		   text.substring(with: NSRange(location: range.location - 2, length: 2)) == "[[",
		   text.substring(with: NSRange(location: NSMaxRange(range), length: 2)) == "]]"
		{
			replaceText(in: NSRange(location: range.location - 2, length: range.length + 4), with: inner)
			selectedRange = NSRange(location: range.location - 2, length: range.length)
		} else {
			replaceText(in: range, with: "[[\(inner)]]")
			selectedRange = NSRange(location: range.location + 2, length: range.length)
		}

		updateReferenceSuggestions(trigger: .explicitTrigger)
	}

	// MARK: - Text Changes and Replacement

	/// Updates layout and suggestions after a native edit.
	///
	/// Does not save the draft.
	func textChanged() {
		textView?.invalidateIntrinsicContentSize()
		updateReferenceSuggestions(trigger: .textEdited)
	}

	/// Applies shortcuts before the native view replaces text.
	///
	/// - Parameter text: Proposed replacement text. An empty string requests deletion.
	/// - Parameter range: Valid range to replace in the native text, in UTF-16 code units.
	/// - Returns: True to allow native replacement; false if the model handles or rejects the replacement.
	func textReplacementRequested(_ text: String, in range: NSRange) -> Bool {
		let currentText = displayedText as NSString

		#if os(iOS)
		// accept suggestions on tab
		if text == "\t", acceptSuggestion() {
			return false
		}
		#endif

		// set heading from "# ", "## ", or "### " prefix
		if let level = headingLevelForShortcut(for: text, range: range, currentText: currentText), handleAction(.setHeading(level)) {
			setText(.raw, text: currentText.substring(from: range.location))
			moveCursor(to: 0)
			endSuggestionSession()
			return false
		}

		// move through character instead of inserting (for auto-closing characters)
		if shouldSkipClosingBracket(for: text, in: displayedText, at: range.location) {
			moveCursor(to: range.location + 1)
			return false
		}

		guard NSMaxRange(range) <= currentText.length else { return true }
		let selected = currentText.substring(with: range)

		// wrap selected text in markdown link when pasting a URL
		if let link = markdownLinkFromPastedURL(for: text, selectedText: selected) {
			replaceText(in: range, with: link)
			let offset = range.location + link.utf16Length
			#if os(iOS)
			// UIKit overrides selectedRange after shouldChangeTextIn returns, so we defer moving the cursor
			DispatchQueue.main.async { [weak self, weak textView] in
				guard let self, let textView, self.textView === textView else { return }
				self.moveCursor(to: offset)
			}
			#else
			moveCursor(to: offset)
			#endif
			textChanged()
			return false
		}

		// Auto-close brackets, or wrap selected text instead of replacing it.
		if let wrapped = wrapWithBrackets(for: text, selectedText: selected) {
			replaceText(in: range, with: wrapped)
			selectedRange = NSRange(location: range.location + 1, length: range.length)
			textChanged()
			return false
		}

		return true
	}

	/// Applies a replacement through the native text editing API.
	///
	/// - Parameter range: Valid range to replace in the native text, in UTF-16 code units.
	/// - Parameter text: Text to insert. An empty string deletes the range.
	private func replaceText(in range: NSRange, with text: String) {
		guard let textView else { return }

		#if os(macOS)
		textView.insertText(text, replacementRange: range)
		#else
		guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
		      let end = textView.position(from: start, offset: range.length),
		      let textRange = textView.textRange(from: start, to: end) else { return }

		textView.replace(textRange, withText: text)
		#endif
	}

	// MARK: - Text Rendering

	/// Sets the native text and its presentation.
	/// Does not save or update `sourceText`.
	///
	/// - Parameter mode: Whether to show raw syntax or rendered text.
	/// - Parameter text: Raw text to display in the requested mode.
	func setText(_ mode: BlockCoordinator.RenderMode, text: String) {
		guard let textView else { return }

		let attributedText: NSAttributedString
		switch mode {
			case .raw:
				pendingFaviconURLs.removeAll()
				attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: labelColor])
			case .rendered:
				let result = buildAttributedString(from: text.strippingTodoPrefix(), font: font, rawStartOffset: text.todoPrefixUTF16Length, faviconProvider: FaviconLoader.image)

				attributedText = result.attributedString
				renderedToRawMapping = result.indexMapping

				let newURLs = result.uncachedFaviconURLs.subtracting(pendingFaviconURLs)
				pendingFaviconURLs.formUnion(newURLs)
				for url in newURLs {
					FaviconLoader.ensureLoaded(faviconURL: url, onSuccess: { [weak self] in
						guard let self else { return }
						self.pendingFaviconURLs.remove(url)
						guard !self.isEditing else { return }
						self.setText(.rendered, text: self.sourceText)
					}, onFailure: { [weak self] in
						self?.pendingFaviconURLs.remove(url)
					})
				}
		}

		#if os(iOS)
		textView.attributedText = attributedText
		#else
		// TODO: Figure out this workaround is still needed
		let delegate = textView.delegate
		textView.delegate = nil
		textView.textStorage?.setAttributedString(attributedText)
		textView.delegate = delegate
		#endif

		textView.invalidateIntrinsicContentSize()
	}

	// MARK: - Reference Suggestions

	/// Asks the parent to accept the current suggestion.
	///
	/// - Returns: True if accepted. The model then ends its suggestion session. Otherwise, returns false.
	private func acceptSuggestion() -> Bool {
		guard onReferenceSuggestionCommand(.accept) else { return false }
		isReferenceSuggestionSessionActive = false
		return true
	}

	/// Clears the suggestion session and sends a nil context to the parent.
	private func endSuggestionSession() {
		isReferenceSuggestionSessionActive = false
		onReferenceSuggestionContextChange(nil, nil)
	}

	/// Updates suggestions from the native text and cursor, or ends the session if no reference is present.
	///
	/// - Parameter trigger: Event that caused the update.
	private func updateReferenceSuggestions(trigger: ReferenceSuggestions.Trigger) {
		if trigger == .selectionChanged, !isReferenceSuggestionSessionActive {
			return
		}

		guard let context = ReferenceSuggestions.Context(in: displayedText, cursorOffset: selectedRange.location) else {
			return endSuggestionSession()
		}

		isReferenceSuggestionSessionActive = true
		#if os(iOS)
		let rect = textView?.caretRectForCurrentSelection()
		#else
		let rect = textView?.caretRectForCurrentSelection(fallbackFont: font)
		#endif
		onReferenceSuggestionContextChange(context, rect)
	}
}

// MARK: - Cursor Geometry

extension EditableTextModel {
	/// Places the cursor at a UTF-16 offset and clears the selection.
	///
	/// - Parameter offset: Requested offset. Will be clamped to the text length.
	func moveCursor(to offset: Int) {
		selectedRange = NSRange(location: clamp(offset, to: 0 ... displayedText.utf16Length), length: 0)
	}

	#if os(iOS)
	/// Finds the horizontal position for movement to an adjacent block.
	///
	/// - Returns: An X coordinate in window coordinates. Negative infinity requests the start of the adjacent block.
	///   Positive infinity requests its end.
	private func cursorXInWindow(textView: UITextView) -> CGFloat {
		guard let selectedRange = textView.selectedTextRange else {
			let xInView = textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
			return textView.convert(CGPoint(x: xInView, y: 0), to: nil).x
		}

		if textView.selectedRange.location == 0 {
			return -.infinity
		}
		if textView.selectedRange.location == textView.attributedText.length {
			return .infinity
		}

		let caretRect = textView.caretRect(for: selectedRange.start)
		return textView.convert(CGPoint(x: caretRect.origin.x, y: 0), to: nil).x
	}

	/// Places the cursor near a window X coordinate on the first or last visual line.
	///
	/// - Parameter windowX: Target horizontal position in window coordinates.
	/// - Parameter edge: First or last visual line of the text.
	/// - Parameter textView: Native view in which to place the cursor.
	private func moveCursorToVisualX(_ windowX: CGFloat, edge: BlockCoordinator.LineEdge, textView: UITextView) {
		let textLength = textView.attributedText.length
		guard textLength > 0 else {
			moveCursor(to: 0)
			return
		}

		textView.layoutManager.ensureLayout(for: textView.textContainer)

		// Find the target line's Y center
		let targetGlyphIndex: Int = switch edge {
			case .first: 0
			case .last: textView.layoutManager.glyphIndexForCharacter(at: textLength - 1)
		}

		let lineRect = textView.layoutManager.lineFragmentRect(forGlyphAt: targetGlyphIndex, effectiveRange: nil)
		let lineY = lineRect.midY + textView.textContainerInset.top

		// Convert window X to text view coordinates
		let pointInView = textView.convert(CGPoint(x: windowX, y: 0), from: nil)
		let targetPoint = CGPoint(x: pointInView.x, y: lineY)

		if let closestPos = textView.closestPosition(to: targetPoint) {
			textView.selectedTextRange = textView.textRange(from: closestPos, to: closestPos)
		}
	}
	#else
	/// Finds the horizontal position for movement to an adjacent block.
	///
	/// - Returns: An X coordinate in window coordinates. Negative infinity requests the start of the adjacent block.
	///   Positive infinity requests its end.
	private func cursorXInWindow(textView: NSTextView) -> CGFloat {
		let cursorLocation = textView.selectedRange().location

		if cursorLocation == 0 {
			return -.infinity
		}
		if cursorLocation == textView.string.utf16Length {
			return .infinity
		}

		guard let layoutManager = textView.layoutManager else {
			return textView.convert(NSPoint(x: textView.textContainerOrigin.x, y: 0), to: nil).x
		}

		let glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorLocation)

		let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
		let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)

		let xInTextContainer = lineRect.origin.x + glyphLocation.x
		let xInView = xInTextContainer + textView.textContainerOrigin.x
		return textView.convert(NSPoint(x: xInView, y: 0), to: nil).x
	}

	/// Places the cursor near a window X coordinate on the first or last visual line.
	///
	/// - Parameter windowX: Target horizontal position in window coordinates.
	/// - Parameter edge: First or last visual line of the text.
	/// - Parameter textView: Native view in which to place the cursor.
	private func moveCursorToVisualX(_ windowX: CGFloat, edge: BlockCoordinator.LineEdge, textView: NSTextView) {
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
	#endif
}

// MARK: - Inline Syntax

private extension EditableTextModel {
	// MARK: Heading Shortcut

	/// Checks for a heading shortcut at the start of the raw text.
	///
	/// - Parameter replacementText: Proposed insertion. The shortcut requires a single space.
	/// - Parameter range: Valid replacement range in UTF-16 code units.
	/// - Parameter currentText: Raw text before the proposed change.
	/// - Returns: Heading level for one to three leading `#` characters followed by a space; nil otherwise.
	func headingLevelForShortcut(for replacementText: String, range: NSRange, currentText: NSString) -> Block.HeadingLevel? {
		guard replacementText == " ", range.length == 0 else { return nil }

		let hashCount = range.location
		guard hashCount >= 1, hashCount <= 3 else { return nil }
		guard currentText.substring(with: NSRange(location: 0, length: hashCount)) == String(repeating: "#", count: hashCount) else { return nil }

		return Block.HeadingLevel(rawValue: hashCount)
	}

	// MARK: Bracket Pairs

	/// Opening brackets and their matching closing brackets.
	private static let bracketPairs: [Character: Character] = [
		"[": "]",
		"(": ")",
	]

	/// Finds an empty bracket pair around the cursor.
	///
	/// - Parameter currentText: Raw text to check for brackets.
	/// - Parameter offset: Cursor offset in UTF-16 code units.
	/// - Returns: Range of both brackets in UTF-16 code units, or nil if no pair exists.
	func bracketPairDeletionRange(in currentText: String, at offset: Int) -> NSRange? {
		guard offset > 0, offset < currentText.utf16Length else { return nil }

		guard let charBefore = currentText.character(beforeUTF16Offset: offset) else { return nil }
		guard let charAfter = currentText.character(atUTF16Offset: offset) else { return nil }
		guard Self.bracketPairs[charBefore] == charAfter else { return nil }

		return NSRange(location: offset - 1, length: 2)
	}

	/// Checks whether typed text matches the closing bracket at the cursor.
	///
	/// - Parameter typedText: Proposed replacement text.
	/// - Parameter currentText: Raw text before replacement.
	/// - Parameter offset: Cursor offset in UTF-16 code units.
	/// - Returns: True for a single matching closing bracket; false otherwise.
	func shouldSkipClosingBracket(for typedText: String, in currentText: String, at offset: Int) -> Bool {
		guard typedText.count == 1, let typedChar = typedText.first, offset < currentText.utf16Length else { return false }
		guard let charAtCursor = currentText.character(atUTF16Offset: offset) else { return false }
		return Self.bracketPairs.values.contains(typedChar) && charAtCursor == typedChar
	}

	/// Adds a matching bracket pair around selected text.
	///
	/// - Parameter typedText: Proposed opening bracket.
	/// - Parameter selectedText: Text to wrap. May be empty.
	/// - Returns: Wrapped text, or nil if the input is not a supported opening bracket.
	func wrapWithBrackets(for typedText: String, selectedText: String) -> String? {
		guard typedText.count == 1, let typedChar = typedText.first, let closingChar = Self.bracketPairs[typedChar] else { return nil }
		return "\(typedChar)\(selectedText)\(closingChar)"
	}

	// MARK: Markdown Links

	/// Builds a Markdown link from selected text and a replacement URL.
	///
	/// - Parameter replacementText: URL text. Must use HTTP or HTTPS and contain no newline.
	/// - Parameter selectedText: Text to use as the link label. Must not be empty.
	/// - Returns: Markdown link, or nil if the URL or selected text does not meet these conditions.
	func markdownLinkFromPastedURL(for replacementText: String, selectedText: String) -> String? {
		guard !selectedText.isEmpty, !replacementText.isEmpty, !replacementText.contains("\n"),
		      let url = URL(string: replacementText), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }

		return "[\(selectedText)](\(replacementText))"
	}
}
