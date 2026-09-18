import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if os(iOS)
struct RenderAsLabel: UIViewRepresentable {
	let text: NSAttributedString

	func makeUIView(context: Context) -> UITextView {
		let textView = AutosizingTextView()
		textView.isEditable = false
		textView.isSelectable = false
		textView.backgroundColor = .clear
		textView.textContainerInset = .zero
		textView.delegate = context.coordinator
		textView.textContainer.lineFragmentPadding = .zero

		return textView
	}

	func updateUIView(_ textView: UITextView, context _: Context) {
		textView.attributedText = text
	}

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	final class Coordinator: NSObject, UITextViewDelegate {
		func textView(_: UITextView, shouldInteractWith _: URL, in _: NSRange) -> Bool {
			return false
		}
	}
}
#else
struct RenderAsLabel: NSViewRepresentable {
	let text: NSAttributedString

	func makeNSView(context _: Context) -> AutosizingTextView {
		let textView = AutosizingTextView()
		textView.isEditable = false
		textView.isSelectable = false
		textView.backgroundColor = .clear

		return textView
	}

	func updateNSView(_ textView: AutosizingTextView, context _: Context) {
		if text != textView.attributedString() {
			textView.textStorage?.setAttributedString(text)
		}
	}
}
#endif
