#if os(iOS)
import UIKit
import SwiftUI
import Dependencies

struct EditableTextView: UIViewRepresentable {
	let model: EditableTextModel
	let blockId: Block.ID?
	let originalText: String
	let alignment: Block.TextAlignment
	let ctFont: CTFont
	let onLinkClicked: (URL) -> Void
	let handleAction: (EditableText.Action) -> Bool
	let onReferenceSuggestionCommand: (ReferenceSuggestions.Command) -> Bool
	let onReferenceSuggestionContextChange: (ReferenceSuggestions.Context?, CGRect?) -> Void

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
		updateModel()
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
				coordinator.model.outdentButtonTapped()
			}),
			UIBarButtonItem(image: UIImage(systemName: "chevron.forward"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.model.indentButtonTapped()
			}),
			UIBarButtonItem(image: UIImage(named: "brackets"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.model.bracketsButtonTapped()
			}),
			UIBarButtonItem(image: UIImage(systemName: "arrow.up"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.model.moveBlockButtonTapped(delta: -1)
			}),
			UIBarButtonItem(image: UIImage(systemName: "arrow.down"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.model.moveBlockButtonTapped(delta: 1)
			}),
			UIBarButtonItem(image: UIImage(systemName: "checkmark.square"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.model.todoButtonTapped()
			}),
			UIBarButtonItem(image: UIImage(systemName: "photo"), primaryAction: UIAction { [weak textView] _ in
				guard let textView, let coordinator = textView.delegate as? Coordinator else { return }
				coordinator.model.photoButtonTapped()
			}),
			UIBarButtonItem(systemItem: .flexibleSpace),
		])

		model.textViewAttached(textView)

		let tapHandler = tap(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleBlockSelected))) {
			$0.delegate = context.coordinator
			$0.isEnabled = selectionCoordinator.hasSelection
		}

		textView.addGestureRecognizer(tapHandler)
		context.coordinator.tapHandler = tapHandler

		return textView
	}

	func updateUIView(_ textView: AutosizingTextView, context: Context) {
		updateModel()
		let alignment = NSTextAlignment(alignment)
		if textView.textAlignment != alignment {
			textView.textAlignment = alignment
		}

		// disable editing when block selection is active
		if selectionCoordinator.hasSelection == textView.isEditable {
			DispatchQueue.main.async {
				textView.isEditable = !selectionCoordinator.hasSelection
				textView.isSelectable = !selectionCoordinator.hasSelection
				context.coordinator.tapHandler?.isEnabled = selectionCoordinator.hasSelection
			}
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(model: model)
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

	static func dismantleUIView(_ uiView: AutosizingTextView, coordinator: Coordinator) {
		coordinator.model.textViewDetached()
		uiView.delegate = nil
	}
}

extension EditableTextView.Coordinator: UITextViewDelegate {
	// MARK: - Focus/Edit Mode Transitions

	func textViewDidBeginEditing(_: UITextView) {
		model.editingBegan()
	}

	func textViewDidChangeSelection(_: UITextView) {
		model.selectionChanged()
	}

	func textViewDidEndEditing(_: UITextView) {
		model.editingEnded()
	}

	// MARK: - Text Changes

	func textViewDidChange(_: UITextView) {
		model.textChanged()
	}

	// MARK: - Link Handling

	func textView(_: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
		guard case let .link(url) = textItem.content else { return defaultAction }
		model.linkPressed()
		return UIAction { [weak model] _ in model?.linkTapped(url) }
	}

	// MARK: - Special Key Handling

	func textView(_: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			return !model.returnPressed(in: range)
		}
		if text.isEmpty {
			if range.location == 0, range.length == 0 {
				return !model.backspacePressed(in: range)
			}
			if range.length == 1, model.backspacePressed(in: NSRange(location: range.location + 1, length: 0)) {
				return false
			}
		}
		return model.textReplacementRequested(text, in: range)
	}
}

extension EditableTextView.Coordinator {
	@objc func handleBlockSelected() {
		model.blockSelected()
	}
}

extension EditableTextView.Coordinator: UIGestureRecognizerDelegate {
	func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
		guard let textView = model.textView, let attributedText = textView.attributedText, attributedText.length > 0 else { return true }

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
		(delegate as? EditableTextView.Coordinator)?.model.tabPressed()
	}

	@objc private func handleBacktab() {
		(delegate as? EditableTextView.Coordinator)?.model.backtabPressed()
	}

	@objc private func handleMoveUp() {
		(delegate as? EditableTextView.Coordinator)?.model.moveBlockButtonTapped(delta: -1)
	}

	@objc private func handleMoveDown() {
		(delegate as? EditableTextView.Coordinator)?.model.moveBlockButtonTapped(delta: 1)
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

		if noModifiers {
			if key.keyCode == .keyboardEscape, coordinator.model.escapePressed() {
				return
			}
			if key.keyCode == .keyboardUpArrow, coordinator.model.upArrowPressed() {
				return
			}
			if key.keyCode == .keyboardDownArrow, coordinator.model.downArrowPressed() {
				return
			}
		}

		super.pressesBegan(presses, with: event)
	}
}
#endif
