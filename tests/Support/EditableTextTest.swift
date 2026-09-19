import Testing
import Foundation
import CoreText
import CustomDump
import DebugSnapshots
import Dependencies

#if canImport(UIKit)
import UIKit
private typealias TextView = UITextView
#else
import AppKit
private typealias TextView = NSTextView
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
			let view = TextView()
			coordinator.setText(.raw, text: raw, textView: view)
			coordinator.isEditing = true

			expect(coordinator) {
				#if canImport(UIKit)
				#expect(!coordinator.textView(view, shouldChangeTextIn: NSRange(location: 13, length: 4), replacementText: "\n"))
				#else
				view.setSelectedRange(NSRange(location: 13, length: 4))
				#expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:))))
				#endif
				if movesFocus { endEditing(coordinator, in: view) }
			} changes: {
				$0.lastKnownText = "🎉 [[World]] "
				$0.isEditing = !movesFocus
			}

			expectNoDifference(events, ["save: 🎉 [[World]] ", "split: 🎉 [[World]] |tail"])
			expectNoDifference(view.displayedText, movesFocus ? "🎉 World " : raw)
		}

		@Test("Merge requests keep raw text through accepted and rejected outcomes", arguments: [false, true])
		func mergeAtStart(accepted: Bool) {
			let raw = "🎉 [[World]]"
			let edited = raw + " edit"
			var events: [String] = []
			let coordinator = makeCoordinator(text: raw) { action in
				switch action {
					case let .mergeIntoPrevious(text):
						events.append("merge: \(text)")
						return accepted
					case let .textChanged(text): events.append("save: \(text)")
					default: Issue.record("Unexpected editor action.")
				}
				return false
			}
			let view = TextView()
			coordinator.setText(.raw, text: edited, textView: view)
			coordinator.isEditing = true

			expect(coordinator) {
				#if canImport(UIKit)
				#expect(!coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: ""))
				#else
				view.setSelectedRange(NSRange(location: 0, length: 0))
				#expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
				#endif
				if accepted { endEditing(coordinator, in: view) }
			} changes: {
				if accepted {
					$0.isEditing = false
					$0.lastKnownText = edited
				}
			}

			expectNoDifference(events, accepted ? ["merge: \(edited)", "save: \(edited)"] : ["merge: \(edited)"])
			expectNoDifference(view.displayedText, accepted ? "🎉 World edit" : edited)
		}

		@Test("Editing restores the raw cursor and clears the previous suggestion session")
		func reopenEditor() {
			let raw = "🎉 [[World]]"
			var suggestions: [String?] = []
			let coordinator = makeCoordinator(text: raw, onSuggestion: { suggestions.append($0?.query) }) { _ in false }
			let view = TextView()
			coordinator.setText(.rendered, text: raw, textView: view)

			expect(coordinator) {
				beginEditing(coordinator, in: view)
			} changes: {
				$0.isEditing = true
			}
			expectNoDifference(view.displayedText, raw)
			expectNoDifference(view.cursorLocation, 5)
			coordinator.isReferenceSuggestionSessionActive = true
			coordinator.activateSuggestionsOnNextTextChange = true

			expect(coordinator) {
				endEditing(coordinator, in: view)
			} changes: {
				$0.isEditing = false
				$0.isReferenceSuggestionSessionActive = false
				$0.activateSuggestionsOnNextTextChange = false
			}
			expectNoDifference(suggestions, [nil])

			expect(coordinator) {
				beginEditing(coordinator, in: view)
			} changes: {
				$0.isEditing = true
			}
			expectNoDifference(view.displayedText, raw)
			expectNoDifference(view.cursorLocation, 5)

			expect(coordinator) {
				#if canImport(UIKit)
				#expect(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 3, length: 0), replacementText: "#"))
				view.textStorage.insert(NSAttributedString(string: "#"), at: 3)
				view.selectedRange = NSRange(location: 6, length: 0)
				coordinator.textViewDidChange(view)
				#else
				#expect(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 3, length: 0), replacementString: "#"))
				view.textStorage?.insert(NSAttributedString(string: "#"), at: 3)
				view.setSelectedRange(NSRange(location: 6, length: 0))
				coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
				#endif
			} changes: {
				$0.isReferenceSuggestionSessionActive = true
			}
			expectNoDifference(suggestions, [nil, "World"])
		}

		private func beginEditing(_ coordinator: EditableTextView.Coordinator, in view: TextView) {
			#if canImport(UIKit)
			view.selectedRange = NSRange(location: 3, length: 0)
			coordinator.willSwitchToEditing = true
			coordinator.textViewDidChangeSelection(view)
			#else
			view.setSelectedRange(NSRange(location: 3, length: 0))
			coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view))
			#endif
		}

		private func endEditing(_ coordinator: EditableTextView.Coordinator, in view: TextView) {
			#if canImport(UIKit)
			coordinator.textViewDidEndEditing(view)
			#else
			coordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: view))
			#endif
		}

		private func makeCoordinator(text: String, onSuggestion: @escaping (ReferenceSuggestions.Context?) -> Void = { _ in }, handleAction: @escaping (EditableText.Action) -> Bool) -> EditableTextView.Coordinator {
			withDependencies {
				$0.blockCoordinator = BlockCoordinator()
			} operation: {
				EditableTextView.Coordinator(parent: EditableTextView(
					blockId: UUID(100), text: text, alignment: .left,
					ctFont: CTFontCreateWithName("Helvetica" as CFString, 13, nil),
					onLinkClicked: { _ in }, handleAction: handleAction,
					onReferenceSuggestionCommand: { _ in false },
					onReferenceSuggestionContextChange: { context, _ in onSuggestion(context) }
				))
			}
		}
	}
}

private extension TextView {
	var displayedText: String {
		#if canImport(UIKit)
		attributedText.string
		#else
		string
		#endif
	}

	var cursorLocation: Int {
		#if canImport(UIKit)
		selectedRange.location
		#else
		selectedRange().location
		#endif
	}
}
