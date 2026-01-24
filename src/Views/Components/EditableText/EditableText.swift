import SwiftUI
import Dependencies

struct EditableText: View {
	enum Action {
		/// Save text changes to database
		case textChanged(String)

		/// Return pressed - break block at cursor. May create new block or outdent.
		case blockBreak(remainingText: String?)

		/// Backspace at start - merge into previous block, appending this content
		case mergeIntoPrevious(appendingContent: String)

		#if os(macOS)
		case indent(cursorPosition: Int)
		case outdent(cursorPosition: Int)
		case moveCursorUp(cursorPosition: Int)
		case moveCursorDown(cursorPosition: Int)
		#endif
	}

	var blockId: Block.ID? = nil
	var text: String
	var handleAction: (Action) -> Bool

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
			onLinkClicked: openLink,
			handleAction: handleAction
		)
		.alignmentGuide(.firstTextBaseline) { _ in
			CTFontGetAscent(ctFont)
		}
	}

	private func openLink(_ url: URL) {
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
		handleAction: { _ in true }
	)
	.padding()
	.preview()
}

#Preview("Long Text") {
	EditableText(
		text: "This is a longer piece of text that might wrap to multiple lines when displayed in the editor.",
		handleAction: { _ in true }
	)
	.padding()
	.preview()
}

#Preview("With Multiple Links") {
	EditableText(
		text: "Check out [[Page One]] and ((abc123456)) and #tag for more info.",
		handleAction: { _ in true }
	)
	.padding()
	.preview()
}
