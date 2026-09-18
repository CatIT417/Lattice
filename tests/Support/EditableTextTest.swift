import Testing
import Foundation
import CoreText
import CustomDump
import Dependencies

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@testable import LatticeDev

extension Tests {
	@MainActor @Suite("Support/EditableText")
	struct EditableTextTest {
		@Test("Splitting a selection saves raw syntax before rendering", arguments: [false, true])
		func splitSelection(movesFocus: Bool) {
			let raw = "🎉 [[World]] cut tail"
			var events: [String] = []
			let coordinator = makeCoordinator(text: raw) { action in
				switch action {
					case let .textChanged(text): events.append("save: \(text)")
					case let .blockBreak(text, remaining):
						events.append("split: \(text)|\(remaining ?? "")")
						return movesFocus
					default: Issue.record("Unexpected editor action.")
				}
				return false
			}
			#if canImport(UIKit)
			let view = UITextView()
			coordinator.setText(.raw, text: raw, textView: view)
			coordinator.isEditing = true
			#expect(!coordinator.textView(view, shouldChangeTextIn: NSRange(location: 13, length: 4), replacementText: "\n"))
			if movesFocus { coordinator.textViewDidEndEditing(view) }
			let displayed = view.attributedText.string
			#else
			let view = NSTextView()
			coordinator.setText(.raw, text: raw, textView: view)
			view.setSelectedRange(NSRange(location: 13, length: 4))
			coordinator.isEditing = true
			#expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:))))
			if movesFocus { coordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: view)) }
			let displayed = view.string
			#endif
			expectNoDifference(events, ["save: 🎉 [[World]] ", "split: 🎉 [[World]] |tail"])
			expectNoDifference(coordinator.lastKnownText, "🎉 [[World]] ")
			expectNoDifference(coordinator.isEditing, !movesFocus)
			expectNoDifference(displayed, movesFocus ? "🎉 World " : raw)
		}

		@Test("Backspace at the start sends raw content to the merge action")
		func mergeAtStart() {
			let raw = "🎉 [[World]]"
			var merged: [String] = []
			let coordinator = makeCoordinator(text: raw) { action in
				guard case let .mergeIntoPrevious(text) = action else {
					Issue.record("Expected a merge action.")
					return false
				}
				merged.append(text)
				return false
			}
			#if canImport(UIKit)
			let view = UITextView()
			coordinator.setText(.raw, text: raw, textView: view)
			#expect(!coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: ""))
			expectNoDifference(view.attributedText.string, raw)
			#else
			let view = NSTextView()
			coordinator.setText(.raw, text: raw, textView: view)
			view.setSelectedRange(NSRange(location: 0, length: 0))
			#expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
			expectNoDifference(view.string, raw)
			#endif
			expectNoDifference(merged, [raw])
		}

		@Test("Editing restores the raw cursor and clears the previous suggestion session")
		func reopenEditor() {
			let raw = "🎉 [[World]]"
			let coordinator = makeCoordinator(text: raw) { _ in false }
			#if canImport(UIKit)
			let view = UITextView()
			coordinator.setText(.rendered, text: raw, textView: view)
			view.selectedRange = NSRange(location: 3, length: 0)
			coordinator.willSwitchToEditing = true
			coordinator.textViewDidChangeSelection(view)
			expectNoDifference(view.attributedText.string, raw)
			expectNoDifference(view.selectedRange.location, 5)
			#else
			let view = NSTextView()
			coordinator.setText(.rendered, text: raw, textView: view)
			view.setSelectedRange(NSRange(location: 3, length: 0))
			coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view))
			expectNoDifference(view.string, raw)
			expectNoDifference(view.selectedRange().location, 5)
			#endif
			#expect(coordinator.isEditing)
			coordinator.isReferenceSuggestionSessionActive = true
			coordinator.activateSuggestionsOnNextTextChange = true
			#if canImport(UIKit)
			coordinator.textViewDidEndEditing(view)
			#else
			coordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: view))
			#endif
			#expect(!coordinator.isEditing)
			#expect(!coordinator.isReferenceSuggestionSessionActive)
			#expect(!coordinator.activateSuggestionsOnNextTextChange)
			coordinator.setText(.raw, text: raw, textView: view)
			#if canImport(UIKit)
			#expect(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "#"))
			#else
			#expect(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "#"))
			#endif
			#expect(coordinator.activateSuggestionsOnNextTextChange)
		}

		private func makeCoordinator(text: String, handleAction: @escaping (EditableText.Action) -> Bool) -> EditableTextView.Coordinator {
			withDependencies {
				$0.blockCoordinator = BlockCoordinator()
			} operation: {
				EditableTextView.Coordinator(parent: EditableTextView(
					blockId: UUID(100), text: text, alignment: .left,
					ctFont: CTFontCreateWithName("Helvetica" as CFString, 13, nil),
					onLinkClicked: { _ in }, handleAction: handleAction,
					onReferenceSuggestionCommand: { _ in false },
					onReferenceSuggestionContextChange: { _, _ in }
				))
			}
		}
	}
}
