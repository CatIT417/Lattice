import SwiftUI
import Dependencies

struct EditableText: View {
	let text: String
	let onSave: (String) -> Void
	let onReturn: (String?) -> Void

	@Environment(\.font) private var font
	@Environment(\.fontResolutionContext) private var fontContext

	@State private var editableText: String

	init(text: String, onSave: @escaping (String) -> Void, onReturn: @escaping (String?) -> Void) {
		self.text = text
		self.onSave = onSave
		self.onReturn = onReturn
		_editableText = State(initialValue: text)
	}

	var body: some View {
		EditableTextView(
			text: $editableText,
			ctFont: (font ?? .body).resolve(in: fontContext).ctFont,
			onSave: onSave,
			onReturn: onReturn,
			onLinkTap: openLink
		)
		.onChange(of: text) { _, newValue in
			editableText = newValue
		}
	}

	func openLink(_ url: URL) {
		// Using .openURL from @Environment causes the view to re-render unexpectedly,
		// so we manually fetch it from EnvironmentValues instead. (rdar://FB13266052)
		EnvironmentValues().openURL(url)
	}
}

#Preview("Display Mode") {
	EditableText(
		text: "Hello [[World]]!",
		onSave: { _ in },
		onReturn: { _ in }
	)
	.padding()
	.preview()
}

#Preview("Long Text") {
	EditableText(
		text: "This is a longer piece of text that might wrap to multiple lines when displayed in the editor.",
		onSave: { _ in },
		onReturn: { _ in }
	)
	.padding()
	.preview()
}

#Preview("With Multiple Links") {
	EditableText(
		text: "Check out [[Page One]] and ((abc123456)) and #tag for more info.",
		onSave: { _ in },
		onReturn: { _ in }
	)
	.padding()
	.preview()
}
