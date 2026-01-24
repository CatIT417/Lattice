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
	let onSave: (String) -> Void
	let onReturn: (String?) -> Void
	let tryDeleteBlock: ((String) -> Bool)?
	let onLinkTap: (URL) -> Void

	@Environment(\.blockCoordinator) var blockCoordinator

	private var nsFont: NSFont {
		ctFont as NSFont
	}

	func makeNSView(context: Context) -> NSTextView {
		let textView = NSTextView(usingTextLayoutManager: false)
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
		textView.textContainer?.widthTracksTextView = true
		textView.textContainer?.heightTracksTextView = true

		textView.setContentHuggingPriority(.required, for: .vertical)
		textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textView.setContentCompressionResistancePriority(.required, for: .vertical)
		textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		context.coordinator.setText(blockCoordinator?.modeFor(blockId: blockId) ?? .rendered, text: text, textView: textView)

		return textView
	}

	func updateNSView(_ textView: NSTextView, context: Context) {
		context.coordinator.parent = self

		if let blockCoordinator, blockCoordinator.shouldFocus(blockId: blockId), textView.window?.firstResponder != textView {
			DispatchQueue.main.async {
				textView.window?.makeFirstResponder(textView)
			}

			if let cursorPosition = blockCoordinator.cursorPositionFor(blockId: blockId) {
				context.coordinator.moveCursorTo(offset: cursorPosition, textView: textView)
			}

			blockCoordinator.clearFocus(for: blockId)
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

	func sizeThatFits(_: ProposedViewSize, nsView _: NSTextView, context _: Context) -> CGSize? {
		// Let SwiftUI use intrinsicContentSize.
		// NSTextView with isVerticallyResizable handles this automatically.
		return nil
	}

	static func dismantleNSView(_ nsView: NSTextView, coordinator: Coordinator) {
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

			// Map cursor from rendered to raw position, or use original offset if no mapping
			// (plain text without references has 1:1 mapping)
			let mappedOffset = indexMapping?.rawIndex(fromRendered: cursorOffset) ?? cursorOffset
			moveCursorTo(offset: min(mappedOffset, parent.text.count), textView: textView)
		}

		fileprivate func deletionRequested(textView: NSTextView) {
			let currentText = textView.attributedString().string
			if let tryDelete = parent.tryDeleteBlock, tryDelete(currentText) {
				textView.window?.makeFirstResponder(nil)
			}
		}

		fileprivate func newBlockRequested(textView: NSTextView, range: NSRange) {
			let currentText = textView.attributedString().string
			let newText = String(currentText.prefix(range.location))

			setText(.rendered, text: newText, textView: textView)
			parent.onReturn(String(currentText.dropFirst(range.location)))
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
			parent.onSave(newText)
		}
		lastKnownText = newText

		setText(.rendered, text: newText, textView: textView)
	}

	// MARK: - Link Handling

	func textView(_ textView: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		linkWasTapped = true

		if let url = link as? URL {
			parent.onLinkTap(url)
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

		return false
	}
}
#endif
