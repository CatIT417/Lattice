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
	let ctFont: CTFont
	let onLinkClicked: (URL) -> Void
	let handleAction: (EditableText.Action) -> Bool

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

		if blockCoordinator.shouldFocus(blockId: blockId), textView.window?.firstResponder != textView {
			let cursorPosition = blockCoordinator.cursorPositionFor(blockId: blockId)

			// View might not be in window yet (e.g., newly created from PlaceholderBlock).
			// Only clear focus after successfully becoming first responder.
			DispatchQueue.main.async { [weak blockCoordinator] in
				guard let window = textView.window else { return }
				window.makeFirstResponder(textView)

				if let cursorPosition {
					context.coordinator.moveCursorTo(offset: cursorPosition, textView: textView)
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
		} else {
			nsView.window?.makeFirstResponder(nil)
		}
	}
}

extension EditableTextView {
	@MainActor class Coordinator: NSObject {
		var parent: EditableTextView
		weak var textView: NSTextView?

		var isEditing = false
		var lastKnownText: String
		var linkWasTapped = false
		var indexMapping: AttributedStringResult.IndexMapping?

		init(parent: EditableTextView) {
			self.parent = parent
			lastKnownText = parent.text
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
					textView.setAttributedText(NSAttributedString(string: text, attributes: [
						.font: parent.nsFont,
						.foregroundColor: NSColor.labelColor,
					]))
				case .rendered:
					let result = buildAttributedString(from: text, font: parent.nsFont)
					indexMapping = result.indexMapping
					textView.setAttributedText(result.attributedString)
			}

			textView.invalidateIntrinsicContentSize()
		}

		func moveCursorTo(offset: Int, textView: NSTextView) {
			let safeOffset = min(max(0, offset), textView.string.count)
			textView.setSelectedRange(NSRange(location: safeOffset, length: 0))
		}

		fileprivate func transitionToEditMode(textView: NSTextView) {
			isEditing = true

			let selectedRange = textView.selectedRange()

			setText(.raw, text: lastKnownText, textView: textView)

			textView.setSelectedRange(indexMapping?.transform(range: selectedRange, maxLength: parent.text.count) ?? selectedRange)

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
			let currentText = textView.attributedString().string
			let newText = String(currentText.prefix(range.location))
			let remainingText = String(currentText.dropFirst(range.location))

			// Save the raw text before switching to rendered mode, otherwise
			// textDidEndEditing will read the rendered text (without [[...]] syntax)
			// and save that to the database, stripping the link formatting.
			_ = parent.handleAction(.textChanged(newText))
			lastKnownText = newText

			let createdNewBlock = parent.handleAction(.blockBreak(remainingText: remainingText.isEmpty ? nil : remainingText))

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

		if linkWasTapped {
			linkWasTapped = false
			textView.window?.makeFirstResponder(nil)
		}
	}

	func textViewDidChangeSelection(_ notification: Notification) {
		guard let textView = notification.object as? NSTextView, !isEditing else { return }
		transitionToEditMode(textView: textView)
	}

	func textDidEndEditing(_ notification: Notification) {
		guard let textView = notification.object as? NSTextView else { return }
		guard isEditing else { return }
		isEditing = false

		let newText = textView.attributedString().string
		if newText != parent.text {
			_ = parent.handleAction(.textChanged(newText))
		}
		lastKnownText = newText

		setText(.rendered, text: newText, textView: textView)
	}

	// MARK: - Link Handling

	func textView(_ textView: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		linkWasTapped = true

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
	}

	func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
		guard let text else { return true }

		if shouldSkipClosingBracket(for: text, in: textView.string, at: range.location) {
			moveCursorTo(offset: range.location + 1, textView: textView)
			return false
		}

		if range.length > 0, let wrappedText = wrapWithBrackets(for: text, selectedText: (textView.string as NSString).substring(with: range)) {
			textView.insertText(wrappedText, replacementRange: range)

			textView.setSelectedRange(NSRange(location: range.location + 1, length: range.length))
			return false
		}

		if let textToInsert = shouldAutoComplete(for: text) {
			textView.insertText(textToInsert, replacementRange: range)
			moveCursorTo(offset: range.location + 1, textView: textView)
			return false
		}

		return true
	}

	// MARK: - Command Handling

	func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		if selector == #selector(NSResponder.cancelOperation(_:)) {
			textView.window?.makeFirstResponder(nil)
			return true
		}

		if selector == #selector(NSResponder.insertNewline(_:)) {
			newBlockRequested(textView: textView, range: textView.selectedRange())
			return true
		}

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

		if selector == #selector(NSResponder.moveUp(_:)), textView.isCursorOnFirstLine(), parent.handleAction(.moveCursorUp(cursorPosition: textView.selectedRange().location)) {
			return true
		}

		if selector == #selector(NSResponder.moveDown(_:)), textView.isCursorOnLastLine(), parent.handleAction(.moveCursorDown(cursorPosition: textView.selectedRange().location)) {
			return true
		}

		if selector == #selector(NSResponder.insertTab(_:)) {
			if parent.blockCoordinator.shouldQueueActions(blockId: parent.blockId) { parent.blockCoordinator.queueAction(.indent) }
			else { _ = parent.handleAction(.indent(cursorPosition: textView.selectedRange().location, currentText: textView.attributedString().string)) }

			return true
		}

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
