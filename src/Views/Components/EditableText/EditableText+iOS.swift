#if os(iOS) || os(visionOS)
import UIKit
import SwiftUI

struct EditableTextView: UIViewRepresentable {
	let blockId: Block.ID?
	let text: String
	let ctFont: CTFont
	let onLinkClicked: (URL) -> Void
	let handleAction: (EditableText.Action) -> Bool

	@Environment(\.blockCoordinator) var blockCoordinator

	private var uiFont: UIFont {
		ctFont as UIFont
	}

	func makeUIView(context: Context) -> AutosizingTextView {
		let textView = AutosizingTextView()
		textView.font = uiFont
		textView.isEditable = true
		textView.textColor = .label
		textView.isSelectable = true
		textView.dataDetectorTypes = []
		textView.isScrollEnabled = false
		textView.backgroundColor = .clear
		textView.textContainerInset = .zero
		textView.delegate = context.coordinator
		context.coordinator.textView = textView
		textView.textContainer.lineFragmentPadding = 0
		textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor]

		textView.setContentHuggingPriority(.required, for: .vertical)
		textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textView.setContentCompressionResistancePriority(.required, for: .vertical)
		textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		textView.withKeyboardActions(items: [
			UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), primaryAction: UIAction { _ in
				context.coordinator.outdent(textView: textView)
			}),
			UIBarButtonItem(image: UIImage(systemName: "chevron.forward"), primaryAction: UIAction { _ in
				context.coordinator.indent(textView: textView)
			}),
			UIBarButtonItem(image: UIImage(named: "brackets"), primaryAction: UIAction { _ in
				context.coordinator.insertBrackets(textView: textView)
			}),
			UIBarButtonItem(image: UIImage(systemName: "arrow.up"), primaryAction: UIAction { _ in
				context.coordinator.moveBlock(textView: textView, delta: -1)
			}),
			UIBarButtonItem(image: UIImage(systemName: "arrow.down"), primaryAction: UIAction { _ in
				context.coordinator.moveBlock(textView: textView, delta: 1)
			}),
			UIBarButtonItem(image: UIImage(systemName: "checkmark.square"), primaryAction: UIAction { _ in
				// TODO: Add checkmark button
			}),
			UIBarButtonItem(image: UIImage(systemName: "photo"), primaryAction: UIAction { _ in
				// TODO: Add photo button
			}),
			UIBarButtonItem(systemItem: .flexibleSpace),
		])

		context.coordinator.setText(blockCoordinator?.modeFor(blockId: blockId) ?? .rendered, text: text, textView: textView)

		return textView
	}

	func updateUIView(_ textView: AutosizingTextView, context: Context) {
		context.coordinator.parent = self

		if let blockCoordinator, blockCoordinator.shouldFocus(blockId: blockId), !textView.isFirstResponder {
			let cursorPosition = blockCoordinator.cursorPositionFor(blockId: blockId)

			// Becoming the first responder synchronously triggers an AttributeGraph cycle
			// when calling BlockCoordinator.request in ParagraphView.moveCursorTo.
			DispatchQueue.main.async { [weak blockCoordinator] in
				guard textView.becomeFirstResponder() else { return }

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
	@MainActor class Coordinator: NSObject {
		var isEditing = false
		var lastKnownText: String
		var linkWasTapped = false
		var parent: EditableTextView
		weak var textView: UITextView?
		var willSwitchToEditing = false
		var indexMapping: AttributedStringResult.IndexMapping?

		init(parent: EditableTextView) {
			self.parent = parent
			lastKnownText = parent.text
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
					textView.attributedText = NSAttributedString(string: text, attributes: [.font: parent.uiFont, .foregroundColor: UIColor.label])
				case .rendered:
					let result = buildAttributedString(from: text, font: parent.uiFont)
					indexMapping = result.indexMapping
					textView.attributedText = result.attributedString
			}

			textView.invalidateIntrinsicContentSize()
		}

		func moveCursorTo(offset: Int, textView: UITextView) {
			if let position = textView.position(from: textView.beginningOfDocument, offset: min(max(0, offset), textView.attributedText.string.count)) {
				textView.selectedTextRange = textView.textRange(from: position, to: position)
			}
		}

		func indent(textView: UITextView) {
			_ = parent.handleAction(.indent(cursorPosition: textView.selectedRange.location))
		}

		func outdent(textView: UITextView) {
			_ = parent.handleAction(.outdent(cursorPosition: textView.selectedRange.location))
		}

		func moveBlock(textView: UITextView, delta: Int) {
			_ = parent.handleAction(.moveBlock(delta: delta, cursorPosition: textView.selectedRange.location))
		}

		func insertBrackets(textView: UITextView) {
			let range = textView.selectedRange
			textView.replace(
				textView.textRange(
					from: textView.position(from: textView.beginningOfDocument, offset: range.location)!,
					to: textView.position(from: textView.beginningOfDocument, offset: range.location + range.length)!
				)!,
				withText: "[[]]"
			)

			moveCursorTo(offset: range.location + 2, textView: textView)
		}

		private func transitionToEditMode(textView: UITextView) {
			isEditing = true
			willSwitchToEditing = false

			var cursorOffset: Int?
			if let selectedRange = textView.selectedTextRange {
				cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
			}

			setText(.raw, text: lastKnownText, textView: textView)

			if let cursorOffset {
				moveCursorTo(offset: min(indexMapping?.rawIndex(fromRendered: cursorOffset) ?? cursorOffset, lastKnownText.count), textView: textView)
			}
		}

		private func deletionRequested(textView: UITextView) {
			let currentText = textView.attributedText.string
			if parent.handleAction(.mergeIntoPrevious(appendingContent: currentText)) {
				textView.resignFirstResponder()
			}
		}

		private func newBlockRequested(textView: UITextView, range: NSRange) {
			let currentText = textView.attributedText.string
			let newText = String(currentText.prefix(range.location))
			let remainingText = String(currentText.dropFirst(range.location))

			// Save the raw text before switching to rendered mode, otherwise
			// textViewDidEndEditing will read the rendered text (without [[...]] syntax)
			// and save that to the database, stripping the link formatting.
			_ = parent.handleAction(.textChanged(newText))
			lastKnownText = newText

			// Only switch to rendered mode if focus moved to a new block
			if parent.handleAction(.blockBreak(remainingText: remainingText.isEmpty ? nil : remainingText)) {
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

		guard !isEditing else { return }

		willSwitchToEditing = true

		// If the user is tapping to place the cursor, `textViewDidChangeSelection` will transition
		// to edit mode. We wait a moment to see if that happens and manually transition if not.
		DispatchQueue.main.async {
			guard self.willSwitchToEditing else { return }
			self.transitionToEditMode(textView: textView)
		}
	}

	func textViewDidChangeSelection(_ textView: UITextView) {
		guard willSwitchToEditing else { return }

		transitionToEditMode(textView: textView)
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		guard isEditing else { return }
		isEditing = false

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
	}

	// MARK: - Special Key Handling

	func textView(
		_ textView: UITextView,
		shouldChangeTextIn range: NSRange,
		replacementText text: String
	) -> Bool {
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

		if text == "\n" {
			newBlockRequested(textView: textView, range: range)
			return false
		}

		if shouldSkipClosingBracket(for: text, in: textView.text ?? "", at: range.location) {
			moveCursorTo(offset: range.location + 1, textView: textView)
			return false
		}

		if range.length > 0, let wrappedText = wrapWithBrackets(for: text, selectedText: (textView.text as NSString).substring(with: range)) {
			textView.replace(
				textView.textRange(
					from: textView.position(from: textView.beginningOfDocument, offset: range.location)!,
					to: textView.position(from: textView.beginningOfDocument, offset: range.location + range.length)!
				)!,
				withText: wrappedText
			)

			textView.selectedRange = NSRange(location: range.location + 1, length: range.length)
			return false
		}

		if let textToInsert = shouldAutoComplete(for: text) {
			textView.replace(
				textView.textRange(
					from: textView.position(from: textView.beginningOfDocument, offset: range.location)!,
					to: textView.position(from: textView.beginningOfDocument, offset: range.location + range.length)!
				)!,
				withText: textToInsert
			)
			moveCursorTo(offset: range.location + 1, textView: textView)
			return false
		}

		return true
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
}
#endif
