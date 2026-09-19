import SwiftUI
import Dependencies

/// Owns one editor model and connects its native view to block actions and reference suggestions.
struct EditableText: View {
	/// Requests a block change or focus transfer from the parent.
	enum Action: Equatable {
		/// Request that the parent save raw text to the database. The editor ignores the result.
		case saveDraft(String)

		/// Return pressed - break block at cursor. May create new block or outdent.
		///
		/// Returns `true` if we should transfer focus or `false` if focus stays on this block.
		case blockBreak(currentText: String, remainingText: String?)

		/// Backspace at start - merge into previous block, appending this content
		///
		/// Returns `true` to end native editing or `false` to keep editing the block.
		case mergeIntoPrevious(appendingContent: String)

		/// Turn this block into a child of the previous block
		case indent(cursorPosition: Int, currentText: String)

		/// Turn this block into a sibling of its parent
		case outdent(cursorPosition: Int, currentText: String)

		/// Move cursor to the closest valid position in the previous line
		///
		/// Returns `true` if we should transfer focus or `false` to allow native arrow-key handling.
		case moveCursorUp(visualX: CGFloat)

		/// Move cursor to the closest valid position in the next line
		///
		/// Returns `true` if we should transfer focus or `false` to allow native arrow-key handling.
		case moveCursorDown(visualX: CGFloat)

		/// Set heading level
		///
		/// Returns `true` if the model should remove the shortcut prefix.
		case setHeading(Block.HeadingLevel)

		#if os(iOS)
		/// Move block up or down, swapping with the adjacent block.
		case moveBlock(delta: Int, cursorPosition: Int, currentText: String)
		#endif
	}

	var blockId: Block.ID?
	var originalText: String
	var alignment: Block.TextAlignment = .left
	var handleAction: (Action) -> Bool

	@State private var model = EditableTextModel()
	@State private var frameInOverlaySpace: CGRect?

	@Environment(\.font) private var font
	@Environment(Router.self) private var router
	@Environment(\.fontResolutionContext) private var fontContext
	@Dependency(\.referenceSuggestionsCoordinator) private var referenceSuggestions

	var body: some View {
		let ctFont = (font ?? .body).resolve(in: fontContext).ctFont

		EditableTextView(
			model: model,
			blockId: blockId,
			originalText: originalText,
			alignment: alignment,
			ctFont: ctFont,
			onLinkClicked: { [router] in Self.openLink($0, using: router) },
			handleAction: handleAction,
			onReferenceSuggestionCommand: { [referenceSuggestions, blockId] in referenceSuggestions.handleCommand($0, from: blockId) },
			onReferenceSuggestionContextChange: { [referenceSuggestions, blockId, frame = $frameInOverlaySpace, handleAction] context, caretRect in
				let currentFrame = frame.wrappedValue

				referenceSuggestions.handleContextChange(
					for: blockId,
					context: context,
					caretRect: caretRect?.offsetBy(dx: currentFrame?.minX ?? 0, dy: currentFrame?.minY ?? 0),
					onTextChanged: { _ = handleAction(.saveDraft($0)) }
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

	private static func openLink(_ url: URL, using router: Router) {
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
		originalText: "Hello [[World]]!",
		handleAction: { _ in true }
	)
	.padding()
	.preview()
}

#Preview("Long Text") {
	EditableText(
		originalText: "This is a longer piece of text that might wrap to multiple lines when displayed in the editor.",
		handleAction: { _ in true }
	)
	.padding()
	.preview()
}

#Preview("With Multiple Links") {
	EditableText(
		originalText: "Check out [[Page One]] and ((abc123456)) and #tag for more info.",
		handleAction: { _ in true }
	)
	.padding()
	.preview()
}
