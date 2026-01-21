import SwiftUI
import Dependencies

struct EditableText: View {
	var blockId: Block.ID? = nil
	var text: String
	var onSave: (String) -> Void
	var onReturn: (String?) -> Void

	@Environment(\.font) private var font
	@Environment(\.fontResolutionContext) private var fontContext

	private var ctFont: CTFont {
		(font ?? .body).resolve(in: fontContext).ctFont
	}

	var body: some View {
		EditableTextView(
			blockId: blockId,
			text: text,
			ctFont: ctFont,
			onSave: onSave,
			onReturn: onReturn,
			onLinkTap: openLink
		)
		.alignmentGuide(.firstTextBaseline) { _ in
			CTFontGetAscent(ctFont)
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
