import SwiftUI
import Dependencies

struct EditableText: View {
	enum Action {
		/// Save text changes to database
		case textChanged(String)

		/// Return pressed - break block at cursor. May create new block or outdent.
		case blockBreak(currentText: String, remainingText: String?)

		/// Backspace at start - merge into previous block, appending this content
		case mergeIntoPrevious(appendingContent: String)

		/// Turn this block into a child of the previous block
		case indent(cursorPosition: Int, currentText: String)

		/// Turn this block into a sibling of its parent
		case outdent(cursorPosition: Int, currentText: String)

		#if os(iOS)
		case moveBlock(delta: Int, cursorPosition: Int, currentText: String)
		#endif

		case moveCursorUp(visualX: CGFloat)
		case moveCursorDown(visualX: CGFloat)
	}

	var blockId: Block.ID? = nil
	var text: String
	var alignment: Block.TextAlignment = .left
	var handleAction: (Action) -> Bool

	@Environment(\.font) private var font
	@Environment(Router.self) private var router
	@Environment(\.fontResolutionContext) private var fontContext

	var body: some View {
		let ctFont = (font ?? .body).resolve(in: fontContext).ctFont

		EditableTextView(
			blockId: blockId,
			text: text,
			alignment: alignment,
			ctFont: ctFont,
			onLinkClicked: openLink,
			handleAction: handleAction
		)
		.alignmentGuide(.firstTextBaseline) { [ascent = CTFontGetAscent(ctFont)] _ in
			ascent
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
