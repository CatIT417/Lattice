#if os(iOS) || os(visionOS)
import UIKit
import SwiftUI

struct EditableTextView: UIViewRepresentable {
	let text: String
	let ctFont: CTFont
	let onSave: (String) -> Void
	let onReturn: (String?) -> Void
	let onLinkTap: (URL) -> Void

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
		textView.textContainer.lineFragmentPadding = 0
		textView.linkTextAttributes = [
			.foregroundColor: UIColor.tintColor,
		]

		textView.setContentHuggingPriority(.required, for: .vertical)
		textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		textView.setContentCompressionResistancePriority(.required, for: .vertical)
		textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		// Start in view mode
		let result = buildAttributedString(from: text, font: uiFont)
		textView.attributedText = result.attributedString
		context.coordinator.indexMapping = result.indexMapping

		return textView
	}

	func updateUIView(_ textView: AutosizingTextView, context: Context) {
		guard !context.coordinator.isEditing, text != context.coordinator.lastKnownText else { return }

		let result = buildAttributedString(from: text, font: uiFont)
		context.coordinator.lastKnownText = text
		textView.attributedText = result.attributedString
		context.coordinator.indexMapping = result.indexMapping

		textView.invalidateIntrinsicContentSize()
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
		var willSwitchToEditing = false

		init(parent: EditableTextView) {
			self.parent = parent
			lastKnownText = parent.text
		}

		// MARK: - Focus/Edit Mode Transitions

		func textViewDidBeginEditing(_ textView: UITextView) {
			if linkWasTapped {
				print("link tapped")
				linkWasTapped = false
				textView.resignFirstResponder()
				return
			}

			guard !isEditing else {
				print("already editing")
				return
			}

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

			willSwitchToEditing = false
			transitionToEditMode(textView: textView)
		}

		private func transitionToEditMode(textView: UITextView) {
			isEditing = true

			var cursorOffset: Int?
			if let selectedRange = textView.selectedTextRange {
				cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
			}

			// Switch to raw text
			textView.attributedText = NSAttributedString(string: parent.text, attributes: [
				.font: parent.uiFont,
				.foregroundColor: UIColor.label,
			])

			if let cursorOffset, let mapping = indexMapping {
				let translatedOffset = min(mapping.rawIndex(fromRendered: cursorOffset), parent.text.count)
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
			textView.invalidateIntrinsicContentSize()
		}

		// MARK: - Return Key Handling

		func textView(
			_ textView: UITextView,
			shouldChangeTextIn _: NSRange,
			replacementText text: String
		) -> Bool {
			guard text == "\n" else { return true }

			let currentText = textView.text ?? ""
			parent.onSave(currentText)
			textView.resignFirstResponder()
			parent.onReturn(nil)
			return false
		}
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
