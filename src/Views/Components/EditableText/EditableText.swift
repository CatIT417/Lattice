import SwiftUI
import Dependencies

struct EditableText: View {
	var blockId: Block.ID? = nil
	var text: String
	var onSave: (String) -> Void
	/// Returns true if a new block was created, false if focus stays on this block (e.g., outdent)
	var onReturn: (String?) -> Bool
	var tryDeleteBlock: ((String) -> Bool)? = nil
	var onMoveUp: ((Int) -> Bool)? = nil
	var onMoveDown: ((Int) -> Bool)? = nil
	var onIndent: ((Int) -> Bool)? = nil
	var onOutdent: ((Int) -> Bool)? = nil

	@Environment(\.font) private var font
	@Environment(Router.self) private var router
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
			tryDeleteBlock: tryDeleteBlock,
			onLinkTap: openLink,
			onMoveUp: onMoveUp,
			onMoveDown: onMoveDown,
			onIndent: onIndent,
			onOutdent: onOutdent
		)
		.alignmentGuide(.firstTextBaseline) { _ in
			CTFontGetAscent(ctFont)
		}
	}

	func openLink(_ url: URL) {
		if url.scheme == Destination.Deeplinks.scheme, router.handleURL(url) {
			// Deeplink handled by app
		} else {
			// Using .openURL from @Environment causes the view to re-render unexpectedly,
			// so we manually fetch it from EnvironmentValues instead. (rdar://FB13266052)
			EnvironmentValues().openURL(url)
		}
	}
}

#Preview("Display Mode") {
	EditableText(
		text: "Hello [[World]]!",
		onSave: { _ in },
		onReturn: { _ in true }
	)
	.padding()
	.preview()
}

#Preview("Long Text") {
	EditableText(
		text: "This is a longer piece of text that might wrap to multiple lines when displayed in the editor.",
		onSave: { _ in },
		onReturn: { _ in true }
	)
	.padding()
	.preview()
}

#Preview("With Multiple Links") {
	EditableText(
		text: "Check out [[Page One]] and ((abc123456)) and #tag for more info.",
		onSave: { _ in },
		onReturn: { _ in true }
	)
	.padding()
	.preview()
}
