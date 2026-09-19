#if os(macOS)
import AppKit
import SwiftUI

struct EditableTextView: NSViewRepresentable {
	let model: EditableTextModel
	let blockId: Block.ID?
	let originalText: String
	let alignment: Block.TextAlignment
	let ctFont: CTFont
	let onLinkClicked: (URL) -> Void
	let handleAction: (EditableText.Action) -> Bool
	let onReferenceSuggestionCommand: (ReferenceSuggestions.Command) -> Bool
	let onReferenceSuggestionContextChange: (ReferenceSuggestions.Context?, CGRect?) -> Void

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
		updateModel()
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

		model.textViewAttached(textView)

		return textView
	}

	func updateNSView(_ textView: AutosizingTextView, context _: Context) {
		updateModel()
		let alignment = NSTextAlignment(alignment)
		if textView.alignment != alignment {
			textView.alignment = alignment
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(model: model)
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
		coordinator.model.textViewDetached()
		nsView.delegate = nil
	}
}

extension EditableTextView.Coordinator: NSTextViewDelegate {
	// MARK: - Focus/Edit Mode Transitions

	func textViewDidChangeSelection(_: Notification) {
		model.selectionChanged()
	}

	func textDidEndEditing(_: Notification) {
		model.editingEnded()
	}

	// MARK: - Link Handling

	func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		guard let url = link as? URL else { return false }
		model.linkTapped(url)
		return true
	}

	// MARK: - Text Changes

	func textDidChange(_: Notification) {
		model.textChanged()
	}

	func textView(_: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
		guard let text else { return true }
		return model.textReplacementRequested(text, in: range)
	}

	// MARK: - Command Handling

	func textView(_: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
			case #selector(NSResponder.insertNewline(_:)): model.returnPressed()
			case #selector(NSResponder.deleteBackward(_:)): model.backspacePressed()
			case #selector(NSResponder.insertTab(_:)): model.tabPressed()
			case #selector(NSResponder.insertBacktab(_:)): model.backtabPressed()
			case #selector(NSResponder.cancelOperation(_:)): model.escapePressed()
			case #selector(NSResponder.moveUp(_:)): model.upArrowPressed()
			case #selector(NSResponder.moveDown(_:)): model.downArrowPressed()
			default: false
		}
	}
}

final class AutosizingTextView: NSTextView {
	var proposedWidth: CGFloat = 0

	override var intrinsicContentSize: NSSize {
		guard let textContainer, let layoutManager else {
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
