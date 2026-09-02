#if os(iOS)
import UIKit
import SwiftUI
import Dependencies

struct EditableTextView: UIViewRepresentable {
	let blockId: Block.ID?
	let text: String
	let alignment: Block.TextAlignment
	let ctFont: CTFont
	let onLinkClicked: (URL) -> Void
	let handleAction: (EditableText.Action) -> Bool
	let onReferenceSuggestionCommand: (ReferenceSuggestions.Command) -> Bool
	let onReferenceSuggestionContextChange: (ReferenceSuggestions.Context?, CGRect?) -> Void

	@Dependency(\.blockCoordinator) var blockCoordinator
	@Dependency(\.blockSelectionCoordinator) var selectionCoordinator

	private var uiFont: UIFont {
		ctFont as UIFont
	}

	func makeUIView(context: Context) -> AutosizingTextView {
		let textView = AutosizingTextView()
		textView.font = uiFont
		textView.textColor = .label
		textView.dataDetectorTypes = []
		textView.isScrollEnabled = false
		textView.backgroundColor = .clear
		textView.textContainerInset = .zero
		textView.delegate = context.coordinator
		context.coordinator.textView = textView
		textView.textContainer.lineFragmentPadding = 0
		textView.textAlignment = NSTextAlignment(alignment)
		textView.isEditable = !selectionCoordinator.hasSelection
		textView.isSelectable = !selectionCoordinator.hasSelection
		textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]

		textView.setContentHuggingPriority(.required, for: .vertical)
		textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textView.setContentCompressionResistancePriority(.required, for: .vertical)
		textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		textView.withKeyboardActions(items: [
			UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.outdent(textView: textView)
			}),
			UIBarButtonItem(image: UIImage(systemName: "chevron.forward"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.indent(textView: textView)
			}),
			UIBarButtonItem(image: UIImage(named: "brackets"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.insertBrackets(textView: textView)
			}),
			UIBarButtonItem(image: UIImage(systemName: "arrow.up"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.moveBlock(textView: textView, delta: -1)
			}),
			UIBarButtonItem(image: UIImage(systemName: "arrow.down"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.moveBlock(textView: textView, delta: 1)
			}),
			UIBarButtonItem(image: UIImage(systemName: "checkmark.square"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.toggleTodo(textView: textView)
			}),
			UIBarButtonItem(image: UIImage(systemName: "photo"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				// TODO: Add photo button
			}),
			UIBarButtonItem(systemItem: .flexibleSpace),
		])

		context.coordinator.setText(blockCoordinator.modeFor(blockId: blockId) ?? .rendered, text: text, textView: textView)

		let tapHandler = tap(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleBlockSelected))) {
			$0.delegate = context.coordinator
			$0.isEnabled = selectionCoordinator.hasSelection
		}

		textView.addGestureRecognizer(tapHandler)
		context.coordinator.tapHandler = tapHandler

		return textView
	}

	func updateUIView(_ textView: AutosizingTextView, context: Context) {
		context.coordinator.parent = self

		// re-render if font changed
		if context.coordinator.lastKnownFont != uiFont {
			context.coordinator.lastKnownFont = uiFont

			let selectedRange = textView.selectedRange
			context.coordinator.setText(
				context.coordinator.isEditing ? .raw : .rendered,
				text: context.coordinator.isEditing ? textView.attributedText.string : context.coordinator.lastKnownText,
				textView: textView
			)
			textView.selectedRange = selectedRange
		}

		let alignment = NSTextAlignment(alignment)
		if alignment != textView.textAlignment { textView.textAlignment = alignment }

		// disable editing when block selection is active
		if selectionCoordinator.hasSelection == textView.isEditable {
			DispatchQueue.main.async {
				textView.isEditable = !selectionCoordinator.hasSelection
				textView.isSelectable = !selectionCoordinator.hasSelection
				context.coordinator.tapHandler?.isEnabled = selectionCoordinator.hasSelection
			}
		}

		if blockCoordinator.shouldFocus(blockId: blockId), !textView.isFirstResponder {
			let placement = blockCoordinator.cursorPlacementFor(blockId: blockId)

			// Becoming the first responder synchronously triggers an AttributeGraph cycle
			// when calling BlockCoordinator.request in ParagraphView.moveCursorTo.
			DispatchQueue.main.async {
				guard textView.becomeFirstResponder() else { return }

				switch placement {
					case let .offset(position): context.coordinator.moveCursorTo(offset: position, textView: textView)
					case let .visualX(x, edge): context.coordinator.moveCursorToVisualX(x, edge: edge, textView: textView)
					case nil: break
				}

				@Dependency(\.blockCoordinator) var blockCoordinator
				blockCoordinator.clearFocus(for: self.blockId)
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

	func sizeThatFits(_ proposal: ProposedViewSize, uiView: AutosizingTextView, context _: Context) -> CGSize? {
		let width = proposal.width ?? 300

		// Store the proposed width so intrinsicContentSize uses the correct value
		if uiView.proposedWidth != width {
			uiView.proposedWidth = width
			uiView.invalidateIntrinsicContentSize()
		}

		let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))

		return CGSize(width: width, height: max(size.height, 22))
	}
}

extension EditableTextView {
	@MainActor final class Coordinator: NSObject {
		var isEditing = false
		var lastKnownText: String
		var lastKnownFont: UIFont
		var linkWasTapped = false
		var parent: EditableTextView
		weak var textView: UITextView?
		var willSwitchToEditing = false
		var pendingFaviconURLs: Set<URL> = []
		weak var tapHandler: UITapGestureRecognizer?
		var isReferenceSuggestionSessionActive = false
		var activateSuggestionsOnNextTextChange = false
		var indexMapping: AttributedStringResult.IndexMapping?

		init(parent: EditableTextView) {
			self.parent = parent
			lastKnownText = parent.text
			lastKnownFont = parent.uiFont
			super.init()

			NotificationCenter.default.addObserver(
				self,
				selector: #selector(saveIfEditing),
				name: .appResignedActive,
				object: nil
			)
		}

		@objc func saveIfEditing() {
			guard isEditing, let textView else { return }
			let newText = textView.attributedText.string
			if newText != parent.text {
				_ = parent.handleAction(.textChanged(newText))
			}
			lastKnownText = newText
		}

		func setText(_ mode: BlockCoordinator.RenderMode, text: String, textView: UITextView) {
			switch mode {
				case .raw:
					pendingFaviconURLs.removeAll()
					textView.attributedText = NSAttributedString(string: text, attributes: [.font: parent.uiFont, .foregroundColor: UIColor.label])
				case .rendered:
					let result = buildAttributedString(from: text.strippingTodoPrefix(), font: parent.uiFont, rawStartOffset: text.todoPrefixUTF16Length, faviconProvider: FaviconLoader.image)
					indexMapping = result.indexMapping
					textView.attributedText = result.attributedString

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

		func moveCursorTo(offset: Int, textView: UITextView) {
			if let position = textView.position(from: textView.beginningOfDocument, offset: clamp(offset, to: 0 ... textView.attributedText.length)) {
				textView.selectedTextRange = textView.textRange(from: position, to: position)
			}
		}

		func updateReferenceSuggestions(textView: UITextView, trigger: ReferenceSuggestions.Trigger, activatingSession: Bool = false) {
			if activatingSession { isReferenceSuggestionSessionActive = true }
			if trigger == .selectionChanged, !isReferenceSuggestionSessionActive { return }

			let context = ReferenceSuggestions.Context(in: textView.attributedText.string, cursorOffset: textView.selectedRange.location)

			if trigger == .textEdited, context != nil {
				isReferenceSuggestionSessionActive = true
			}

			if let context, isReferenceSuggestionSessionActive {
				parent.onReferenceSuggestionContextChange(context, textView.caretRectForCurrentSelection())
			} else {
				if context == nil { isReferenceSuggestionSessionActive = false }
				parent.onReferenceSuggestionContextChange(nil, nil)
			}
		}

		func cursorXInWindow(textView: UITextView) -> CGFloat {
			guard let selectedRange = textView.selectedTextRange else {
				let xInView = textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
				return textView.convert(CGPoint(x: xInView, y: 0), to: nil).x
			}

			if textView.selectedRange.location == 0 { return -.infinity }
			if textView.selectedRange.location == textView.attributedText.length { return .infinity }

			let caretRect = textView.caretRect(for: selectedRange.start)
			return textView.convert(CGPoint(x: caretRect.origin.x, y: 0), to: nil).x
		}

		func moveCursorToVisualX(_ windowX: CGFloat, edge: BlockCoordinator.LineEdge, textView: UITextView) {
			let textLength = textView.attributedText.length
			guard textLength > 0 else {
				moveCursorTo(offset: 0, textView: textView)
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

		func indent(textView: UITextView) {
			lastKnownText = textView.attributedText.string
			_ = parent.handleAction(.indent(cursorPosition: textView.selectedRange.location, currentText: lastKnownText))
		}

		func outdent(textView: UITextView) {
			lastKnownText = textView.attributedText.string
			_ = parent.handleAction(.outdent(cursorPosition: textView.selectedRange.location, currentText: lastKnownText))
		}

		func moveBlock(textView: UITextView, delta: Int) {
			lastKnownText = textView.attributedText.string
			_ = parent.handleAction(.moveBlock(delta: delta, cursorPosition: textView.selectedRange.location, currentText: lastKnownText))
		}

		func toggleTodo(textView: UITextView) {
			guard isEditing else { return }

			let oldText = textView.attributedText.string
			let cursorPosition = textView.selectedRange.location

			let newState = oldText.todoState.next
			let newText = oldText.withTodoState(newState)

			_ = parent.handleAction(.textChanged(newText))
			lastKnownText = newText
			setText(.raw, text: newText, textView: textView)

			let oldPrefixLen = oldText.todoPrefixUTF16Length
			let newPrefixLen = newState?.prefixUTF16Length ?? 0
			moveCursorTo(offset: max(0, cursorPosition + newPrefixLen - oldPrefixLen), textView: textView)
		}

		func moveCursorUp(textView: UITextView) -> Bool {
			return parent.handleAction(.moveCursorUp(visualX: cursorXInWindow(textView: textView)))
		}

		func moveCursorDown(textView: UITextView) -> Bool {
			return parent.handleAction(.moveCursorDown(visualX: cursorXInWindow(textView: textView)))
		}

		func insertBrackets(textView: UITextView) {
			let range = textView.selectedRange
			let text = textView.text as NSString

			if range.location >= 2, range.location + range.length + 2 <= text.length,
			   text.substring(with: NSRange(location: range.location - 2, length: 2)) == "[[",
			   text.substring(with: NSRange(location: range.location + range.length, length: 2)) == "]]"
			{
				textView.selectedRange = NSRange(location: range.location - 2, length: range.length + 4)
				textView.insertText(text.substring(with: range))
				textView.selectedRange = NSRange(location: range.location - 2, length: range.length)
				updateReferenceSuggestions(textView: textView, trigger: .explicitTrigger, activatingSession: true)
				return
			}

			let inner = range.length > 0 ? text.substring(with: range) : ""
			textView.insertText("[[\(inner)]]")
			textView.selectedRange = NSRange(location: range.location + 2, length: range.length)
			updateReferenceSuggestions(textView: textView, trigger: .explicitTrigger, activatingSession: true)
		}

		@objc func handleBlockSelected() {
			guard let blockId = parent.blockId else { return }

			UIImpactFeedbackGenerator(style: .light).impactOccurred()
			withAnimation(parent.selectionCoordinator.animation) {
				parent.selectionCoordinator.toggleSelection(on: blockId)
			}
		}

		private func transitionToEditMode(textView: UITextView) {
			isEditing = true
			willSwitchToEditing = false
			parent.blockCoordinator.editingStarted(for: parent.blockId)

			var cursorOffset: Int?
			if let selectedRange = textView.selectedTextRange {
				cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
			}

			setText(.raw, text: lastKnownText, textView: textView)

			if let cursorOffset {
				moveCursorTo(offset: min(indexMapping?.rawIndex(fromRendered: cursorOffset) ?? cursorOffset, lastKnownText.utf16Length), textView: textView)
			}
		}

		private func deletionRequested(textView: UITextView) {
			let currentText = textView.attributedText.string
			if parent.handleAction(.mergeIntoPrevious(appendingContent: currentText)) {
				textView.resignFirstResponder()
			}
		}

		private func newBlockRequested(textView: UITextView, range: NSRange) {
			let currentText = textView.attributedText.string as NSString
			let newText = currentText.substring(to: range.location)
			let remainingText = currentText.substring(from: range.location + range.length)

			// Save the raw text before switching to rendered mode, otherwise
			// textViewDidEndEditing will read the rendered text (without [[...]] syntax)
			// and save that to the database, stripping the link formatting.
			_ = parent.handleAction(.textChanged(newText))
			lastKnownText = newText

			// Only switch to rendered mode if focus moved to a new block
			if parent.handleAction(.blockBreak(currentText: newText, remainingText: remainingText.isEmpty ? nil : remainingText)) {
				isEditing = false
				textView.resignFirstResponder()
				setText(.rendered, text: newText, textView: textView)
			}
		}
	}
}

extension EditableTextView.Coordinator: UITextViewDelegate {
	// MARK: - Focus/Edit Mode Transitions

	func textViewDidBeginEditing(_ textView: UITextView) {
		if linkWasTapped {
			linkWasTapped = false
			textView.resignFirstResponder()
			return
		}

		guard !isEditing, !parent.selectionCoordinator.hasSelection else { return }

		willSwitchToEditing = true

		// If the user is tapping to place the cursor, `textViewDidChangeSelection` will transition
		// to edit mode. We wait a moment to see if that happens and manually transition if not.
		DispatchQueue.main.async {
			guard self.willSwitchToEditing else { return }
			self.transitionToEditMode(textView: textView)
		}
	}

	func textViewDidChangeSelection(_ textView: UITextView) {
		if willSwitchToEditing { return transitionToEditMode(textView: textView) }

		updateReferenceSuggestions(textView: textView, trigger: .selectionChanged)
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		isReferenceSuggestionSessionActive = false
		activateSuggestionsOnNextTextChange = false
		parent.onReferenceSuggestionContextChange(nil, nil)

		guard isEditing else { return }
		isEditing = false
		parent.blockCoordinator.editingEnded(for: parent.blockId)

		let newText = textView.attributedText.string
		if newText != parent.text {
			_ = parent.handleAction(.textChanged(newText))
		}
		lastKnownText = newText

		setText(.rendered, text: newText, textView: textView)
	}

	// MARK: - Link Handling

	func textView(
		_: UITextView,
		primaryActionFor textItem: UITextItem,
		defaultAction: UIAction
	) -> UIAction? {
		if case let .link(url) = textItem.content {
			linkWasTapped = true
			return UIAction { [weak self] _ in
				self?.parent.onLinkClicked(url)
			}
		}

		return defaultAction
	}

	// MARK: - Text Changes

	func textViewDidChange(_ textView: UITextView) {
		textView.invalidateIntrinsicContentSize()

		updateReferenceSuggestions(textView: textView, trigger: .textEdited, activatingSession: activateSuggestionsOnNextTextChange)
		activateSuggestionsOnNextTextChange = false
	}

	// MARK: - Special Key Handling

	func textView(
		_ textView: UITextView,
		shouldChangeTextIn range: NSRange,
		replacementText text: String
	) -> Bool {
		// accept suggestions on enter/tab
		if text == "\n" || text == "\t", parent.onReferenceSuggestionCommand(.accept) {
			isReferenceSuggestionSessionActive = false
			activateSuggestionsOnNextTextChange = false
			return false
		}

		let currentText = textView.attributedText.string as NSString
		if shouldActivateReferenceSuggestionSession(for: text, range: range, currentText: currentText) {
			activateSuggestionsOnNextTextChange = true
		}

		if text.isEmpty {
			if range.location == 0, range.length == 0 {
				deletionRequested(textView: textView)
				return false
			}

			if range.length == 1, let rangeToDelete = shouldAutoDelete(in: textView.text ?? "", at: range.location + 1) {
				textView.replace(
					textView.textRange(
						from: textView.position(from: textView.beginningOfDocument, offset: rangeToDelete.location)!,
						to: textView.position(from: textView.beginningOfDocument, offset: rangeToDelete.location + rangeToDelete.length)!
					)!,
					withText: ""
				)
				moveCursorTo(offset: rangeToDelete.location, textView: textView)
				return false
			}
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

		// create new block
		if text == "\n" {
			newBlockRequested(textView: textView, range: range)
			return false
		}

		// move through character instead of inserting (for auto-closing characters)
		if shouldSkipClosingBracket(for: text, in: textView.text ?? "", at: range.location) {
			moveCursorTo(offset: range.location + 1, textView: textView)
			return false
		}

		// wrap selected text in markdown link when pasting a URL
		if range.length > 0, range.location + range.length <= (textView.text as NSString).length,
		   let markdownLink = markdownLinkFromPastedURL(for: text, selectedText: (textView.text as NSString).substring(with: range))
		{
			textView.replace(
				textView.textRange(
					from: textView.position(from: textView.beginningOfDocument, offset: range.location)!,
					to: textView.position(from: textView.beginningOfDocument, offset: range.location + range.length)!
				)!,
				withText: markdownLink
			)

			updateReferenceSuggestions(
				textView: textView,
				trigger: .textEdited,
				activatingSession: activateSuggestionsOnNextTextChange
			)
			activateSuggestionsOnNextTextChange = false

			// UIKit overrides selectedRange after shouldChangeTextIn returns, so we defer moving the cursor
			let cursorOffset = range.location + markdownLink.utf16.count
			DispatchQueue.main.async { [weak self, weak textView] in
				guard let textView else { return }
				self?.moveCursorTo(offset: cursorOffset, textView: textView)
			}

			return false
		}

		// wrap text with brackets instead of replacing it
		if range.length > 0, range.location + range.length <= (textView.text as NSString).length,
		   let wrappedText = wrapWithBrackets(for: text, selectedText: (textView.text as NSString).substring(with: range))
		{
			textView.replace(
				textView.textRange(
					from: textView.position(from: textView.beginningOfDocument, offset: range.location)!,
					to: textView.position(from: textView.beginningOfDocument, offset: range.location + range.length)!
				)!,
				withText: wrappedText
			)

			textView.selectedRange = NSRange(location: range.location + 1, length: range.length)
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
			textView.replace(
				textView.textRange(
					from: textView.position(from: textView.beginningOfDocument, offset: range.location)!,
					to: textView.position(from: textView.beginningOfDocument, offset: range.location + range.length)!
				)!,
				withText: textToInsert
			)
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
}

extension EditableTextView.Coordinator: UIGestureRecognizerDelegate {
	func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
		guard let textView, let attributedText = textView.attributedText, attributedText.length > 0 else { return true }

		let characterIndex = textView.layoutManager.characterIndex(
			for: recognizer.location(in: textView),
			in: textView.textContainer,
			fractionOfDistanceBetweenInsertionPoints: nil
		)
		guard characterIndex >= 0, characterIndex < attributedText.length else { return true }

		let tappedLink = attributedText.attribute(
			.link,
			at: characterIndex,
			effectiveRange: nil
		) as? NSURL

		return tappedLink == nil
	}
}

final class AutosizingTextView: UITextView {
	/// Width to use for sizing, set by SwiftUI's sizeThatFits
	var proposedWidth: CGFloat = 0

	/// The last width used during layout
	private var lastLayoutWidth: CGFloat = 0

	init() {
		// Force TextKit 1
		super.init(frame: .zero, textContainer: nil)
	}

	override var keyCommands: [UIKeyCommand]? {
		[
			UIKeyCommand(title: "Indent Block", action: #selector(handleTab), input: "\t"),
			UIKeyCommand(title: "Outdent Block", action: #selector(handleBacktab), input: "\t", modifierFlags: .shift),
			UIKeyCommand(title: "Move Block Up", action: #selector(handleMoveUp), input: UIKeyCommand.inputUpArrow, modifierFlags: [.control, .command]),
			UIKeyCommand(title: "Move Block Down", action: #selector(handleMoveDown), input: UIKeyCommand.inputDownArrow, modifierFlags: [.control, .command]),
		]
	}

	@objc private func handleTab() {
		guard let coordinator = delegate as? EditableTextView.Coordinator else { return }

		if coordinator.parent.onReferenceSuggestionCommand(.accept) {
			coordinator.isReferenceSuggestionSessionActive = false
			return
		}

		coordinator.indent(textView: self)
	}

	@objc private func handleBacktab() {
		guard let coordinator = delegate as? EditableTextView.Coordinator else { return }

		coordinator.outdent(textView: self)
	}

	@objc private func handleMoveUp() {
		guard let coordinator = delegate as? EditableTextView.Coordinator else { return }

		coordinator.moveBlock(textView: self, delta: -1)
	}

	@objc private func handleMoveDown() {
		guard let coordinator = delegate as? EditableTextView.Coordinator else { return }

		coordinator.moveBlock(textView: self, delta: 1)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// Uses proposed width from SwiftUI, then bounds, then fallback
	override var intrinsicContentSize: CGSize {
		let fixedWidth = proposedWidth > 0 ? proposedWidth : (bounds.width > 0 ? bounds.width : 300)
		let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
		return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, 22))
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		if bounds.width != lastLayoutWidth {
			lastLayoutWidth = bounds.width
			invalidateIntrinsicContentSize()
		}
	}

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		guard let key = presses.first?.key, let coordinator = delegate as? EditableTextView.Coordinator else {
			super.pressesBegan(presses, with: event)
			return
		}

		let modifiers: UIKeyModifierFlags = [.shift, .control, .alternate, .command]
		let noModifiers = key.modifierFlags.intersection(modifiers).isEmpty

		// close suggestions panel
		if key.keyCode == .keyboardEscape, noModifiers, coordinator.parent.onReferenceSuggestionCommand(.dismiss) {
			coordinator.isReferenceSuggestionSessionActive = false
			return
		}

		// previous suggestion
		if key.keyCode == .keyboardUpArrow, noModifiers, coordinator.parent.onReferenceSuggestionCommand(.moveUp) {
			return
		}

		// next suggestion
		if key.keyCode == .keyboardDownArrow, noModifiers, coordinator.parent.onReferenceSuggestionCommand(.moveDown) {
			return
		}

		// move to previous block
		if key.keyCode == .keyboardUpArrow, noModifiers, isCursorOnFirstLine(), coordinator.moveCursorUp(textView: self) {
			return
		}

		// move to next block
		if key.keyCode == .keyboardDownArrow, noModifiers, isCursorOnLastLine(), coordinator.moveCursorDown(textView: self) {
			return
		}

		super.pressesBegan(presses, with: event)
	}
}
#endif
