#if os(macOS)
import AppKit
import SwiftUI

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

	@Environment(\.blockCoordinator) var blockCoordinator

	private var nsFont: NSFont {
		ctFont as NSFont
	}

	func makeNSView(context: Context) -> AutosizingTextView {
		let textView = AutosizingTextView(usingTextLayoutManager: false)
		textView.font = nsFont
		textView.isEditable = true
		textView.isSelectable = true
		textView.drawsBackground = false
		textView.textContainerInset = .zero
		textView.delegate = context.coordinator
		textView.isRichText = false
		textView.importsGraphics = false
		textView.isAutomaticLinkDetectionEnabled = false
		textView.isAutomaticQuoteSubstitutionEnabled = true
		textView.isAutomaticDashSubstitutionEnabled = true
		textView.isAutomaticTextReplacementEnabled = true
		textView.isAutomaticSpellingCorrectionEnabled = true
		textView.typingAttributes = [
			.font: nsFont,
			.foregroundColor: NSColor.labelColor,
		]
		textView.linkTextAttributes = [
			.cursor: NSCursor.pointingHand,
			.foregroundColor: NSColor.systemBlue,
		]

		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
		textView.textContainer?.widthTracksTextView = false
		textView.textContainer?.heightTracksTextView = false
		textView.textContainer?.lineFragmentPadding = 0

		textView.setContentHuggingPriority(.required, for: .vertical)
		textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textView.setContentCompressionResistancePriority(.required, for: .vertical)
		textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		context.coordinator.setText(blockCoordinator?.modeFor(blockId: blockId) ?? .rendered, text: text, textView: textView)

		return textView
	}

	func updateNSView(_ textView: AutosizingTextView, context: Context) {
		context.coordinator.parent = self

		if let blockCoordinator, blockCoordinator.shouldFocus(blockId: blockId), textView.window?.firstResponder != textView {
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

		if context.coordinator.lastKnownText != text, let expectsNewText = blockCoordinator?.expectsNewText(for: blockId), expectsNewText || !context.coordinator.isEditing {
			context.coordinator.lastKnownText = text
			context.coordinator.setText(blockCoordinator?.modeFor(blockId: blockId) ?? .rendered, text: text, textView: textView)
			if let cursorPosition = blockCoordinator?.cursorPositionFor(blockId: blockId) {
				context.coordinator.moveCursorTo(offset: cursorPosition, textView: textView)
			}
			blockCoordinator?.textReceived(for: blockId)
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView: AutosizingTextView, context _: Context) -> CGSize? {
		let width = proposal.width ?? 300

		if nsView.proposedWidth != width {
			nsView.proposedWidth = width
			nsView.invalidateIntrinsicContentSize()
		}

		guard let textContainer = nsView.textContainer, let layoutManager = nsView.layoutManager else {
			return nil
		}

		textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
		layoutManager.ensureLayout(for: textContainer)

		let usedRect = layoutManager.usedRect(for: textContainer)
		return CGSize(width: width, height: max(usedRect.height, 22))
	}

	static func dismantleNSView(_ nsView: AutosizingTextView, coordinator: Coordinator) {
		// When SwiftUI tears down the view, force end editing to ensure text is saved
		if coordinator.isEditing {
			nsView.window?.makeFirstResponder(nil)
		}
	}
}

extension EditableTextView {
	@MainActor class Coordinator: NSObject {
		var parent: EditableTextView
		var isEditing = false
		var lastKnownText: String
		var indexMapping: IndexMapping?
		var linkWasTapped = false

		init(parent: EditableTextView) {
			self.parent = parent
			lastKnownText = parent.text
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

			let cursorOffset = textView.selectedRange().location

			setText(.raw, text: lastKnownText, textView: textView)

			let mappedOffset = indexMapping?.rawIndex(fromRendered: cursorOffset) ?? cursorOffset
			moveCursorTo(offset: min(mappedOffset, parent.text.count), textView: textView)

			if let pendingAction = parent.blockCoordinator?.popAction(for: parent.blockId) {
				switch pendingAction {
					case .indent: _ = parent.handleAction(.indent(cursorPosition: textView.selectedRange().location))
					case .outdent: _ = parent.handleAction(.outdent(cursorPosition: textView.selectedRange().location))
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

		if let action = shouldAutoComplete(for: text, in: textView.string, at: range.location) {
			textView.insertText(action.textToInsert, replacementRange: range)
			moveCursorTo(offset: range.location + action.cursorOffset, textView: textView)
			return false
		}

		return true
	}

	// MARK: - Command Handling

	func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
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
		}

		if selector == #selector(NSResponder.moveUp(_:)), textView.isCursorOnFirstLine(), parent.handleAction(.moveCursorUp(cursorPosition: textView.selectedRange().location)) {
			return true
		}

		if selector == #selector(NSResponder.moveDown(_:)), textView.isCursorOnLastLine(), parent.handleAction(.moveCursorDown(cursorPosition: textView.selectedRange().location)) {
			return true
		}

		if selector == #selector(NSResponder.insertTab(_:)) {
			if parent.blockCoordinator?.shouldQueueActions(blockId: parent.blockId) ?? false { parent.blockCoordinator?.queueAction(.indent) }
			else { _ = parent.handleAction(.indent(cursorPosition: textView.selectedRange().location)) }

			return true
		}

		if selector == #selector(NSResponder.insertBacktab(_:)) {
			if parent.blockCoordinator?.shouldQueueActions(blockId: parent.blockId) ?? false { parent.blockCoordinator?.queueAction(.outdent) }
			else { _ = parent.handleAction(.outdent(cursorPosition: textView.selectedRange().location)) }

			return true
		}

		return false
	}
}

final class AutosizingTextView: NSTextView {
	var proposedWidth: CGFloat = 0
	private var lastLayoutWidth: CGFloat = 0

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

	override func layout() {
		super.layout()
		if bounds.width != lastLayoutWidth {
			lastLayoutWidth = bounds.width
			invalidateIntrinsicContentSize()
		}
	}
}
#endif
