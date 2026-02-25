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

		/// Move cursor to the closest valid position in the previous line
		case moveCursorUp(visualX: CGFloat)

		/// Move cursor to the closest valid position in the next line
		case moveCursorDown(visualX: CGFloat)

		/// Set heading level
		case setHeading(Block.HeadingLevel)

		#if os(iOS)
		/// Move block up or down, swapping with the adjacent block.
		case moveBlock(delta: Int, cursorPosition: Int, currentText: String)
		#endif
	}

	var blockId: Block.ID? = nil
	var text: String
	var alignment: Block.TextAlignment = .left
	var handleAction: (Action) -> Bool

	@State private var frameInOverlaySpace: CGRect?

	@Environment(\.font) private var font
	@Environment(Router.self) private var router
	@Environment(\.fontResolutionContext) private var fontContext
	@Dependency(\.referenceSuggestionsCoordinator) private var referenceSuggestions

	var body: some View {
		let ctFont = (font ?? .body).resolve(in: fontContext).ctFont

		EditableTextView(
			blockId: blockId,
			text: text,
			alignment: alignment,
			ctFont: ctFont,
			onLinkClicked: openLink,
			handleAction: handleAction,
			onReferenceSuggestionCommand: { referenceSuggestions.handleCommand($0, from: blockId) },
			onReferenceSuggestionContextChange: { context, caretRect in
				referenceSuggestions.handleContextChange(
					for: blockId,
					context: context,
					caretRect: caretRect.map(overlayCaretRect(from:)),
					onTextChanged: { _ = handleAction(.textChanged($0)) }
				)
			}
		)
		.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(ReferenceSuggestions.coordinateSpace)) }) { newFrame in
			if let previousFrame = frameInOverlaySpace {
				referenceSuggestions.offsetAnchor(for: blockId, by: CGSize(width: newFrame.minX - previousFrame.minX, height: newFrame.minY - previousFrame.minY))
			}

			frameInOverlaySpace = newFrame
		}
		.alignmentGuide(.firstTextBaseline) { [ascent = CTFontGetAscent(ctFont)] _ in
			ascent
		}
		.onDisappear { referenceSuggestions.endEditing(for: blockId) }
	}

	private func overlayCaretRect(from localRect: CGRect) -> CGRect {
		let frame = frameInOverlaySpace ?? .zero

		return CGRect(
			x: frame.minX + localRect.minX, y: frame.minY + localRect.minY,
			width: localRect.width, height: localRect.height
		)
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
