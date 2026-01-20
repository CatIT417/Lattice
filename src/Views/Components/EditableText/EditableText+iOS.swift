#if os(iOS) || os(visionOS)
import UIKit
import SwiftUI

/// Custom UITextView that properly sizes itself for SwiftUI
final class AutosizingTextView: UITextView {
	/// The width to use for sizing, set by SwiftUI's sizeThatFits
	var proposedWidth: CGFloat = 0
	private var lastLayoutWidth: CGFloat = 0

	/// Stores the last tap location for cursor positioning during mode transitions
	var lastTapLocation: CGPoint?

	/// Force TextKit 1 for better performance with dynamic sizing
	init() {
		super.init(frame: .zero, textContainer: nil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: CGSize {
		// Use proposed width from SwiftUI, then bounds, then fallback
		let fixedWidth = proposedWidth > 0 ? proposedWidth : (bounds.width > 0 ? bounds.width : 300)
		let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
		return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, 22))
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		// Only invalidate when width actually changes
		if bounds.width != lastLayoutWidth {
			lastLayoutWidth = bounds.width
			invalidateIntrinsicContentSize()
		}
	}
}

struct EditableTextView: UIViewRepresentable {
	@Binding var text: String
	let ctFont: CTFont
	let onSave: (String) -> Void
	let onReturn: (String?) -> Void
	let onLinkTap: (URL) -> Void

	private var uiFont: UIFont {
		ctFont as UIFont
	}

	func makeUIView(context: Context) -> AutosizingTextView {
		let textView = AutosizingTextView()
		textView.delegate = context.coordinator
		textView.backgroundColor = .clear
		textView.textContainerInset = .zero
		textView.textContainer.lineFragmentPadding = 0
		textView.isScrollEnabled = false
		textView.isEditable = true
		textView.isSelectable = true
		textView.dataDetectorTypes = []
		textView.linkTextAttributes = [
			.foregroundColor: UIColor.tintColor,
		]

		// Layout priorities for proper SwiftUI integration
		textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textView.setContentHuggingPriority(.required, for: .vertical)
		textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		textView.setContentCompressionResistancePriority(.required, for: .vertical)

		// Start in view mode (attributed text)
		let result = buildAttributedString(from: text, font: uiFont)
		textView.attributedText = result.attributedString
		context.coordinator.indexMapping = result.indexMapping

		return textView
	}

	func updateUIView(_ textView: AutosizingTextView, context: Context) {
		// Only update if text changed externally and not editing
		if !context.coordinator.isEditing, text != context.coordinator.lastKnownText {
			let result = buildAttributedString(from: text, font: uiFont)
			textView.attributedText = result.attributedString
			context.coordinator.indexMapping = result.indexMapping
			context.coordinator.lastKnownText = text
			textView.invalidateIntrinsicContentSize()
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
	@MainActor class Coordinator: NSObject, UITextViewDelegate {
		var parent: EditableTextView
		var isEditing = false
		var lastKnownText: String
		var indexMapping: IndexMapping?
		var linkWasTapped = false
		var isSwitchingModes = false

		init(parent: EditableTextView) {
			self.parent = parent
			lastKnownText = parent.text
		}

		// MARK: - Focus/Edit Mode Transitions

		func textViewDidBeginEditing(_ textView: UITextView) {
			// If a link was tapped, don't enter edit mode
			if linkWasTapped {
				linkWasTapped = false
				textView.resignFirstResponder()
				return
			}

			guard !isEditing else { return }
			isSwitchingModes = true
		}

		func textViewDidChangeSelection(_ textView: UITextView) {
			guard isSwitchingModes else { return }

			isSwitchingModes = false
			transitionToEditMode(textView: textView)
		}

		private func transitionToEditMode(textView: UITextView) {
			isEditing = true

			var cursorOffset: Int?
			if let selectedRange = textView.selectedTextRange {
				cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
			}

			// Switch to raw text
			let rawText = parent.text
			textView.text = rawText
			textView.font = parent.uiFont
			textView.textColor = .label

			if let cursorOffset, let mapping = indexMapping {
				let translatedOffset = min(mapping.rawIndex(fromRendered: cursorOffset), rawText.count)
				if let translatedPosition = textView.position(from: textView.beginningOfDocument, offset: translatedOffset) {
					textView.selectedTextRange = textView.textRange(from: translatedPosition, to: translatedPosition)
				}
			}

			textView.invalidateIntrinsicContentSize()
		}

		func textViewDidEndEditing(_ textView: UITextView) {
			guard isEditing else { return }
			isEditing = false

			let newText = textView.text ?? ""
			if newText != parent.text {
				parent.text = newText
				parent.onSave(newText)
			}
			lastKnownText = newText

			// Switch back to rendered mode
			let result = buildAttributedString(from: newText, font: parent.uiFont)
			textView.attributedText = result.attributedString
			indexMapping = result.indexMapping

			textView.invalidateIntrinsicContentSize()
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
					self?.parent.onLinkTap(url)
				}
			}

			return defaultAction
		}

		// MARK: - Text Changes

		func textViewDidChange(_ textView: UITextView) {
			// Invalidate size when text changes during editing
			textView.invalidateIntrinsicContentSize()
		}

		// MARK: - Return Key Handling

		func textView(
			_ textView: UITextView,
			shouldChangeTextIn _: NSRange,
			replacementText text: String
		) -> Bool {
			guard text == "\n" else { return true }

			// Commit current edit and trigger new block
			let currentText = textView.text ?? ""
			parent.text = currentText
			parent.onSave(currentText)
			textView.resignFirstResponder()
			parent.onReturn(nil) // TODO: Split text based on cursor position
			return false
		}
	}
}
#endif
