import Testing
import CoreText
import CustomDump
import Foundation
import SQLiteData
import Dependencies
import DebugSnapshots
import DependenciesTestSupport

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@testable import LatticeDev

extension Tests {
	@MainActor @Suite("Support/EditableText")
	struct EditableTextTest {
		// MARK: - View Updates and Attachment

		@Test("Incoming text does not overwrite the active draft")
		func incomingText() {
			let editor = Editor("old")
			editor.setNativeText("draft", selection: NSRange(location: 3, length: 0))

			expect(editor) { editor.update("remote") } changes: { _ in }

			editor.blockCoordinator.request(for: UUID(100), at: 2, expectsNewText: true, startingInMode: .raw)
			expect(editor) { editor.update("accepted") } changes: {
				$0.state.sourceText = "accepted"
				$0.state.displayedText = "accepted"
				$0.state.selectedRange = NSRange(location: 2, length: 0)
			}

			#expect(!editor.blockCoordinator.expectsNewText(for: UUID(100)))
		}

		@Test("Idle editors receive updated source text")
		func idleUpdate() {
			let editor = Editor("old", editing: false)

			expect(editor) { editor.update("[[World]]") } changes: {
				$0.state.displayedText = "World"
				$0.state.sourceText = "[[World]]"
				$0.state.selectedRange = NSRange(location: 5, length: 0)
			}
		}

		@Test("Font updates preserve the current draft and selection")
		func fontUpdate() {
			let editor = Editor("old")
			editor.setNativeText("🎉 draft", selection: NSRange(location: 3, length: 5))

			expect(editor) { editor.update("old", fontSize: 24) } changes: { _ in }
		}

		@Test("A detached editor retains the latest original text for attachment")
		func updateBeforeAttachment() {
			let editor = Editor("old", editing: false)
			editor.model.textViewDetached()

			expect(editor) { editor.update("[[World]]") } changes: {
				$0.state.sourceText = "[[World]]"
			}

			expect(editor) { editor.model.textViewAttached(editor.textView) } changes: {
				$0.state.displayedText = "World"
				$0.state.selectedRange = NSRange(location: 5, length: 0)
			}
		}

		// MARK: - Focus and Editing Lifecycle

		@Test("Reopening maps the cursor and clears the suggestion session")
		func reopenEditor() {
			let editor = Editor("🎉 [[World]]", editing: false, selection: NSRange(location: 3, length: 0))

			expect(editor) { editor.beginEditing() } changes: {
				$0.state.isEditing = true
				$0.activeBlockID = UUID(100)
				$0.state.displayedText = "🎉 [[World]]"
				$0.state.selectedRange = NSRange(location: 5, length: 0)
			}

			expect(editor) { editor.model.textChanged() } changes: {
				$0.state.isReferenceSuggestionSessionActive = true
				$0.contexts.append(.init(kind: .pageLink, query: "World", fullText: "🎉 [[World]]", cursorOffset: 5, queryRange: NSRange(location: 5, length: 5), tokenRange: NSRange(location: 3, length: 9)))
			}

			expect(editor) { editor.model.editingEnded() } changes: {
				$0.activeBlockID = nil
				$0.contexts.append(nil)
				$0.state.isEditing = false
				$0.state.displayedText = "🎉 World"
				$0.actions.append(.saveDraft("🎉 [[World]]"))
				$0.state.isReferenceSuggestionSessionActive = false
				$0.state.selectedRange = NSRange(location: 8, length: 0)
			}

			editor.model.selectedRange = NSRange(location: 3, length: 0)
			expect(editor) { editor.beginEditing() } changes: {
				$0.state.isEditing = true
				$0.activeBlockID = UUID(100)
				$0.state.displayedText = "🎉 [[World]]"
				$0.state.selectedRange = NSRange(location: 5, length: 0)
			}

			expect(editor) { editor.model.selectionChanged() } changes: { _ in }
		}

		@Test("Reopening uses the retained source text length before the parent updates")
		func reopenLongerDraft() {
			let editor = Editor("short")
			editor.setNativeText("[[World]] 🎉", selection: NSRange(location: 12, length: 0))
			editor.model.editingEnded()
			editor.model.selectedRange = NSRange(location: 8, length: 0)

			expect(editor) { editor.beginEditing() } changes: {
				$0.state.isEditing = true
				$0.activeBlockID = UUID(100)
				$0.state.displayedText = "[[World]] 🎉"
				$0.state.selectedRange = NSRange(location: 12, length: 0)
			}
		}

		@Test("App deactivation saves the raw draft without ending editing")
		func saveDraft() {
			let editor = Editor("old")
			editor.setNativeText("🎉 [[World]]", selection: NSRange(location: 3, length: 0))

			expect(editor) { editor.model.appResignedActive() } changes: {
				$0.state.sourceText = "🎉 [[World]]"
				$0.actions.append(.saveDraft("🎉 [[World]]"))
			}
		}

		@Test("Unchanged drafts still request a save while editing")
		func unchangedDraft() {
			let editor = Editor("text")

			expect(editor) { editor.model.appResignedActive() } changes: {
				$0.actions.append(.saveDraft("text"))
			}

			expect(editor) { editor.model.editingEnded() } changes: {
				$0.activeBlockID = nil
				$0.contexts.append(nil)
				$0.state.isEditing = false
				$0.actions.append(.saveDraft("text"))
				#if os(macOS)
				$0.state.selectedRange = NSRange(location: 4, length: 0)
				#endif
			}

			expect(editor) { editor.model.appResignedActive() } changes: { _ in }
		}

		@Test("Detaching during focus transfer saves and clears the session")
		func detachEditor() async {
			let editor = Editor("old")
			editor.setNativeText("draft", selection: NSRange(location: 3, length: 0))
			editor.blockCoordinator.request(for: UUID(100), at: 3, startingInMode: .raw)

			await expect(editor) {
				editor.model.focusRequested()
				editor.model.textViewDetached()
				await nextMainQueueTurn()
			} changes: {
				$0.activeBlockID = nil
				$0.contexts.append(nil)
				$0.state.isEditing = false
				$0.state.displayedText = ""
				$0.state.sourceText = "draft"
				$0.actions.append(.saveDraft("draft"))
				$0.state.selectedRange = NSRange(location: 0, length: 0)
			}

			#expect(editor.model.textView == nil)
		}

		@Test("Focus requests remain pending until the view has a window")
		func focusWithoutWindow() async {
			let editor = Editor("text", editing: false)
			editor.blockCoordinator.request(for: UUID(100), at: 2, startingInMode: .raw)

			await expect(editor) {
				editor.model.focusRequested()
				await nextMainQueueTurn()
			} changes: { _ in }

			#expect(editor.blockCoordinator.shouldFocus(blockId: UUID(100)))
		}

		#if os(iOS)
		@Test("Ending editing cancels a deferred edit transition")
		func cancelDeferredEditing() async {
			let editor = Editor("[[World]]", editing: false)

			expect(editor) { editor.model.editingBegan() } changes: { $0.state.isEditTransitionPending = true }

			await expect(editor) {
				editor.model.editingEnded()
				await nextMainQueueTurn()
			} changes: {
				$0.contexts.append(nil)
				$0.state.isEditTransitionPending = false
			}
		}
		#endif

		// MARK: - Parent Persistence

		@Test("The parent skips database writes for unchanged drafts", .dependencies { try $0.bootstrapDatabase() })
		func unchangedDraftDoesNotWrite() throws {
			@Dependency(\.defaultDatabase) var database

			let paragraph = try storedParagraph()
			let editor = Editor(paragraph.string)
			editor.onAction = ParagraphView(paragraph: paragraph).handleAction
			let changes = try database.write { $0.totalChangesCount }

			expect(editor) {
				editor.model.appResignedActive()
				editor.model.appResignedActive()
			} changes: {
				$0.actions = [.saveDraft("original"), .saveDraft("original")]
			}

			try expectNoDifference(database.write { $0.totalChangesCount }, changes)
		}

		@Test("Saves use the stored text before the parent view updates", .dependencies { try $0.bootstrapDatabase() })
		func saveBeforeParentUpdate() throws {
			@Dependency(\.defaultDatabase) var database

			let paragraph = try storedParagraph()
			let editor = Editor(paragraph.string)
			editor.onAction = ParagraphView(paragraph: paragraph).handleAction
			editor.model.todoButtonTapped()
			let changes = try database.write { $0.totalChangesCount }

			expect(editor) { editor.model.appResignedActive() } changes: {
				$0.actions.append(.saveDraft("{{[[TODO]]}} original"))
			}
			try expectNoDifference(database.write { $0.totalChangesCount }, changes)

			expect(editor) {
				editor.model.todoButtonTapped()
				editor.model.todoButtonTapped()
			} changes: {
				$0.actions.append(.saveDraft("{{[[DONE]]}} original"))
				$0.actions.append(.saveDraft("original"))
				$0.state.sourceText = "original"
				$0.state.displayedText = "original"
				$0.state.selectedRange = NSRange(location: 0, length: 0)
			}

			try expectNoDifference(
				database.read { try Paragraph.find(paragraph.id).select(\.string).fetchOne($0) },
				"original"
			)
		}

		@Test("A rejected block action does not prevent saving the draft", .dependencies { try $0.bootstrapDatabase() }, arguments: [false, true])
		func saveAfterRejectedAction(outdent: Bool) throws {
			@Dependency(\.defaultDatabase) var database

			let paragraph = try storedParagraph()
			let parent = ParagraphView(paragraph: paragraph)
			let editor = Editor(paragraph.string)
			editor.onAction = { action in
				guard case .saveDraft = action else { return false }
				return parent.handleAction(action)
			}
			editor.setNativeText("draft", selection: NSRange(location: 5, length: 0))

			expect(editor) {
				if outdent {
					editor.model.outdentButtonTapped()
				} else {
					editor.model.indentButtonTapped()
				}
			} changes: {
				$0.state.sourceText = "draft"
				$0.actions.append(outdent ? .outdent(cursorPosition: 5, currentText: "draft") : .indent(cursorPosition: 5, currentText: "draft"))
			}

			try expectNoDifference(
				database.read { try Paragraph.find(paragraph.id).select(\.string).fetchOne($0) },
				"original"
			)

			expect(editor) { editor.model.appResignedActive() } changes: {
				$0.actions.append(.saveDraft("draft"))
			}

			try expectNoDifference(
				database.read { try Paragraph.find(paragraph.id).select(\.string).fetchOne($0) },
				"draft"
			)
		}

		@Test("Saving compares against remote text without replacing the active draft", .dependencies { try $0.bootstrapDatabase() }, arguments: ["original", "local draft"])
		func saveAfterRemoteUpdate(draft: String) throws {
			@Dependency(\.defaultDatabase) var database

			let paragraph = try storedParagraph()
			let editor = Editor(paragraph.string)
			editor.setNativeText(draft, selection: NSRange(location: 0, length: 0))
			try database.write { db in
				try Block.find(paragraph.id).update { $0.string = #bind("remote") }.execute(db)
			}
			let updatedParagraph = try #require(database.read { try Paragraph.find(paragraph.id).fetchOne($0) })
			editor.onAction = ParagraphView(paragraph: updatedParagraph).handleAction

			expect(editor) { editor.update(updatedParagraph.string) } changes: { _ in }
			expect(editor) { editor.model.appResignedActive() } changes: {
				$0.actions.append(.saveDraft(draft))
				$0.state.sourceText = draft
			}

			try expectNoDifference(
				database.read { try Paragraph.find(paragraph.id).select(\.string).fetchOne($0) },
				draft
			)
		}

		// MARK: - Keyboard Actions

		@Test("Return saves raw syntax before splitting a selection", arguments: [false, true])
		func splitSelection(movesFocus: Bool) {
			let editor = Editor("🎉 [[World]] cut tail", selection: NSRange(location: 13, length: 4))
			editor.onAction = {
				if case .blockBreak = $0 {
					return movesFocus
				}; return false
			}

			expect(editor) {
				#expect(editor.model.returnPressed())
			} changes: {
				$0.commands.append(.accept)
				$0.state.sourceText = "🎉 [[World]] "
				$0.actions = [.saveDraft("🎉 [[World]] "), .blockBreak(currentText: "🎉 [[World]] ", remainingText: "tail")]
				if movesFocus {
					$0.state.isEditing = false
					$0.state.displayedText = "🎉 World "
					$0.state.selectedRange = NSRange(location: 9, length: 0)
				}
			}

			if movesFocus {
				expect(editor) { editor.model.editingEnded() } changes: { $0.contexts.append(nil) }
			}
		}

		@Test("Return at the end sends no remaining text")
		func splitAtEnd() {
			let editor = Editor("hello", selection: NSRange(location: 5, length: 0))

			expect(editor) { #expect(editor.model.returnPressed()) } changes: {
				$0.commands.append(.accept)
				$0.actions = [.saveDraft("hello"), .blockBreak(currentText: "hello", remainingText: nil)]
			}
		}

		@Test("Merge preserves raw text for accepted and rejected requests", arguments: [false, true])
		func mergeAtStart(accepted: Bool) {
			let editor = Editor("🎉 [[World]]")
			editor.setNativeText("🎉 [[World]] edit", selection: NSRange(location: 0, length: 0))
			editor.onAction = {
				if case .mergeIntoPrevious = $0 {
					return accepted
				}; return false
			}

			expect(editor) { #expect(editor.model.backspacePressed()) } changes: {
				$0.actions.append(.mergeIntoPrevious(appendingContent: "🎉 [[World]] edit"))
			}
			if accepted {
				expect(editor) { editor.model.editingEnded() } changes: {
					$0.activeBlockID = nil
					$0.state.isEditing = false
					$0.contexts.append(nil)
					$0.state.displayedText = "🎉 World edit"
					$0.state.sourceText = "🎉 [[World]] edit"
					$0.actions.append(.saveDraft("🎉 [[World]] edit"))
					$0.state.selectedRange = NSRange(location: 13, length: 0)
				}
			}
		}

		@Test("Tab and Shift-Tab send the current text and UTF-16 cursor")
		func indentAndOutdent() {
			let editor = Editor("old")
			editor.setNativeText("🎉 draft", selection: NSRange(location: 3, length: 0))

			expect(editor) { #expect(editor.model.tabPressed()) } changes: {
				$0.commands.append(.accept)
				$0.state.sourceText = "🎉 draft"
				$0.actions.append(.indent(cursorPosition: 3, currentText: "🎉 draft"))
			}

			expect(editor) { #expect(editor.model.backtabPressed()) } changes: {
				$0.actions.append(.outdent(cursorPosition: 3, currentText: "🎉 draft"))
			}
		}

		@Test("Arrow keys pass the start and end positions to block navigation")
		func arrowNavigation() {
			let editor = Editor("text")
			editor.onAction = { _ in true }

			expect(editor) { #expect(editor.model.upArrowPressed()) } changes: {
				$0.commands.append(.moveUp)
				$0.actions.append(.moveCursorUp(visualX: -.infinity))
			}

			editor.model.moveCursor(to: 4)
			expect(editor) { #expect(editor.model.downArrowPressed()) } changes: {
				$0.commands.append(.moveDown)
				$0.actions.append(.moveCursorDown(visualX: .infinity))
			}
		}

		@Test("Native Return delegates use the correct handled result")
		func returnDelegate() {
			let editor = Editor("text")
			expect(editor) {
				#if os(iOS)
				#expect(!editor.coordinator.textView(editor.textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "\n"))
				#else
				#expect(editor.coordinator.textView(editor.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
				#endif
			} changes: {
				$0.state.sourceText = ""
				$0.commands.append(.accept)
				$0.actions = [.saveDraft(""), .blockBreak(currentText: "", remainingText: "text")]
			}
		}

		@Test("Native deletion delegates remove bracket pairs")
		func deleteDelegate() {
			let editor = Editor("🎉 []", selection: NSRange(location: 4, length: 0))

			expect(editor) {
				#if os(iOS)
				#expect(!editor.coordinator.textView(editor.textView, shouldChangeTextIn: NSRange(location: 3, length: 1), replacementText: ""))
				#else
				#expect(editor.coordinator.textView(editor.textView, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
				#endif
			} changes: {
				$0.state.displayedText = "🎉 "
				$0.state.selectedRange = NSRange(location: 3, length: 0)
			}
		}

		// MARK: - Toolbar and Link Actions

		@Test("The bracket button wraps and unwraps the selection")
		func bracketsButton() {
			let editor = Editor("word", selection: NSRange(location: 0, length: 4))

			expect(editor) { editor.model.bracketsButtonTapped() } changes: {
				$0.state.displayedText = "[[word]]"
				$0.state.isReferenceSuggestionSessionActive = true
				$0.state.selectedRange = NSRange(location: 2, length: 4)
				$0.contexts.append(.init(kind: .pageLink, query: "word", fullText: "[[word]]", cursorOffset: 2, queryRange: NSRange(location: 2, length: 4), tokenRange: NSRange(location: 0, length: 8)))
			}

			expect(editor) { editor.model.bracketsButtonTapped() } changes: {
				$0.contexts.append(nil)
				$0.state.displayedText = "word"
				$0.state.isReferenceSuggestionSessionActive = false
				$0.state.selectedRange = NSRange(location: 0, length: 4)
			}
		}

		@Test("The todo button preserves the cursor relative to the content")
		func todoButton() {
			let editor = Editor("🎉 text", selection: NSRange(location: 3, length: 0))

			expect(editor) { editor.model.todoButtonTapped() } changes: {
				$0.state.sourceText = "{{[[TODO]]}} 🎉 text"
				$0.state.displayedText = "{{[[TODO]]}} 🎉 text"
				$0.actions.append(.saveDraft("{{[[TODO]]}} 🎉 text"))
				$0.state.selectedRange = NSRange(location: 16, length: 0)
			}
		}

		@Test("The todo button advances through all states")
		func todoCycle() {
			let editor = Editor("{{[[TODO]]}} text", selection: NSRange(location: 15, length: 0))

			expect(editor) { editor.model.todoButtonTapped() } changes: {
				$0.state.sourceText = "{{[[DONE]]}} text"
				$0.state.displayedText = "{{[[DONE]]}} text"
				$0.actions.append(.saveDraft("{{[[DONE]]}} text"))
			}

			expect(editor) { editor.model.todoButtonTapped() } changes: {
				$0.state.sourceText = "text"
				$0.state.displayedText = "text"
				$0.actions.append(.saveDraft("text"))
				$0.state.selectedRange = NSRange(location: 2, length: 0)
			}

			let idleEditor = Editor("text", editing: false)
			expect(idleEditor) { idleEditor.model.todoButtonTapped() } changes: { _ in }
		}

		@Test("Link actions reach the current callback")
		func linkTapped() throws {
			let editor = Editor("text")
			let url = try #require(URL(string: "lattice://page/World"))

			expect(editor) { editor.model.linkTapped(url) } changes: { $0.openedURLs.append(url) }
		}

		#if os(iOS)
		@Test("A link press does not start editing")
		func linkPress() {
			let editor = Editor("[[World]]", editing: false)

			expect(editor) { editor.model.linkPressed() } changes: { $0.state.linkWasTapped = true }
			expect(editor) { editor.model.editingBegan() } changes: { $0.state.linkWasTapped = false }
		}

		@Test("Move buttons send the current draft and cursor", arguments: [-1, 1])
		func moveBlock(delta: Int) {
			let editor = Editor("old")
			editor.setNativeText("draft", selection: NSRange(location: 2, length: 0))

			expect(editor) { editor.model.moveBlockButtonTapped(delta: delta) } changes: {
				$0.state.sourceText = "draft"
				$0.actions.append(.moveBlock(delta: delta, cursorPosition: 2, currentText: "draft"))
			}
		}
		#endif

		#if os(macOS)
		@Test("Indentation waits for the pending editor", arguments: [false, true])
		func queuedIndentation(outdent: Bool) {
			let editor = Editor("old")
			editor.blockCoordinator.request(for: UUID(101), at: 0, startingInMode: .raw)

			expect(editor) {
				if outdent {
					editor.model.outdentButtonTapped()
				} else {
					editor.model.indentButtonTapped()
				}
			} changes: { _ in }

			editor.model.editingEnded()
			editor.model.moveCursor(to: 0)
			editor.blockCoordinator.request(for: UUID(100), at: 0, startingInMode: .raw)
			expect(editor) { editor.beginEditing() } changes: {
				$0.state.isEditing = true
				$0.activeBlockID = UUID(100)
				$0.actions.append(outdent ? .outdent(cursorPosition: 0, currentText: "old") : .indent(cursorPosition: 0, currentText: "old"))
			}

			expectNoDifference(editor.blockCoordinator.popAction(for: UUID(100)), nil)
		}
		#endif

		// MARK: - Text Changes and Replacement

		@Test("Ordinary edits remain native", arguments: ["x", "hello\nworld", "file:///tmp/file", ""])
		func ordinaryReplacement(text: String) {
			let editor = Editor("word", selection: NSRange(location: 1, length: 2))

			expect(editor) {
				#expect(editor.model.textReplacementRequested(text, in: editor.model.selectedRange))
				#expect(!editor.model.backspacePressed())
			} changes: { _ in }
		}

		@Test("Opening brackets insert a pair", arguments: [("[", "🎉 []"), ("(", "🎉 ()")])
		func bracketPair(typed: String, expected: String) {
			let editor = Editor("🎉 ", selection: NSRange(location: 3, length: 0))

			expect(editor) {
				#expect(!editor.model.textReplacementRequested(typed, in: editor.model.selectedRange))
			} changes: {
				$0.contexts.append(nil)
				$0.state.displayedText = expected
				$0.state.selectedRange = NSRange(location: 4, length: 0)
			}
		}

		@Test("Bracket input wraps a selection", arguments: [("[", "🎉 [word]"), ("(", "🎉 (word)")])
		func wrapSelection(typed: String, expected: String) {
			let editor = Editor("🎉 word", selection: NSRange(location: 3, length: 4))

			expect(editor) {
				#expect(!editor.model.textReplacementRequested(typed, in: editor.model.selectedRange))
			} changes: {
				$0.contexts.append(nil)
				$0.state.displayedText = expected
				$0.state.selectedRange = NSRange(location: 4, length: 4)
			}
		}

		@Test("Closing bracket input moves through the existing bracket", arguments: ["[]", "()"])
		func skipClosingBracket(text: String) {
			let editor = Editor(text, selection: NSRange(location: 1, length: 0))

			expect(editor) {
				#expect(!editor.model.textReplacementRequested(String(text.suffix(1)), in: editor.model.selectedRange))
			} changes: { $0.state.selectedRange = NSRange(location: 2, length: 0) }
		}

		@Test("Backspace deletes a bracket pair", arguments: ["🎉 []", "🎉 ()"])
		func deletePair(text: String) {
			let editor = Editor(text, selection: NSRange(location: 4, length: 0))
			expect(editor) { #expect(editor.model.backspacePressed()) } changes: {
				$0.state.displayedText = "🎉 "
				$0.state.selectedRange = NSRange(location: 3, length: 0)
			}
		}

		@Test("A pasted URL wraps selected text and places the cursor after the link")
		func pasteURL() async {
			let editor = Editor("🎉 word!", selection: NSRange(location: 3, length: 4))

			await expect(editor) {
				#expect(!editor.model.textReplacementRequested("https://example.com", in: editor.model.selectedRange))
				await nextMainQueueTurn()
			} changes: {
				$0.contexts.append(nil)
				$0.state.displayedText = "🎉 [word](https://example.com)!"
				$0.state.selectedRange = NSRange(location: 30, length: 0)
			}
		}

		@Test("Heading shortcuts remove the prefix", arguments: [("#", Block.HeadingLevel.h1), ("##", .h2), ("###", .h3)])
		func headingShortcut(prefix: String, level: Block.HeadingLevel) {
			let editor = Editor(prefix + "title", selection: NSRange(location: prefix.utf16.count, length: 0))
			editor.onAction = { _ in true }

			expect(editor) {
				#expect(!editor.model.textReplacementRequested(" ", in: editor.model.selectedRange))
			} changes: {
				$0.contexts.append(nil)
				$0.state.displayedText = "title"
				$0.actions.append(.setHeading(level))
				$0.state.selectedRange = NSRange(location: 0, length: 0)
			}
		}

		@Test("A rejected heading shortcut preserves the native edit")
		func rejectedHeading() {
			let editor = Editor("#title", selection: NSRange(location: 1, length: 0))

			expect(editor) {
				#expect(editor.model.textReplacementRequested(" ", in: editor.model.selectedRange))
			} changes: { $0.actions.append(.setHeading(.h1)) }
		}

		// MARK: - Reference Suggestions

		@Test("Suggestions take priority over Return and Tab", arguments: [false, true])
		func acceptSuggestion(tab: Bool) {
			let editor = Editor("[[World]]", selection: NSRange(location: 4, length: 0))
			editor.model.textChanged()
			editor.onCommand = { _ in true }

			expect(editor) {
				#expect(tab ? editor.model.tabPressed() : editor.model.returnPressed())
			} changes: {
				$0.commands.append(.accept)
				$0.state.isReferenceSuggestionSessionActive = false
			}
		}

		@Test("Escape dismisses suggestions until the next edit")
		func dismissSuggestions() {
			let editor = Editor("[[World]]", selection: NSRange(location: 4, length: 0))
			editor.model.textChanged()
			editor.onCommand = { _ in true }

			expect(editor) { #expect(editor.model.escapePressed()) } changes: {
				$0.commands.append(.dismiss)
				$0.state.isReferenceSuggestionSessionActive = false
			}

			expect(editor) { editor.model.selectionChanged() } changes: { _ in }

			expect(editor) { editor.model.textChanged() } changes: {
				$0.state.isReferenceSuggestionSessionActive = true
				$0.contexts.append(.init(kind: .pageLink, query: "World", fullText: "[[World]]", cursorOffset: 4, queryRange: NSRange(location: 2, length: 5), tokenRange: NSRange(location: 0, length: 9)))
			}
		}

		@Test("Arrow keys give suggestions priority", arguments: [false, true])
		func arrowSuggestions(down: Bool) {
			let editor = Editor("text")
			editor.onCommand = { _ in true }

			expect(editor) { #expect(down ? editor.model.downArrowPressed() : editor.model.upArrowPressed()) } changes: {
				$0.commands.append(down ? .moveDown : .moveUp)
			}
		}

		@Test("A tag edit activates suggestions and moving outside ends the session")
		func tagSession() {
			let editor = Editor("")

			expect(editor) {
				#expect(editor.model.textReplacementRequested("#", in: editor.model.selectedRange))
			} changes: { _ in }

			editor.setNativeText("#tag ", selection: NSRange(location: 4, length: 0))
			expect(editor) { editor.model.textChanged() } changes: {
				$0.state.isReferenceSuggestionSessionActive = true
				$0.contexts.append(.init(kind: .tagSimple, query: "tag", fullText: "#tag ", cursorOffset: 4, queryRange: NSRange(location: 1, length: 3), tokenRange: NSRange(location: 0, length: 4)))
			}

			editor.model.moveCursor(to: 5)
			expect(editor) { editor.model.selectionChanged() } changes: {
				$0.contexts.append(nil)
				$0.state.isReferenceSuggestionSessionActive = false
			}
		}

		@Test("A second opening bracket starts a page-link session")
		func pageLinkSession() {
			let editor = Editor("[]", selection: NSRange(location: 1, length: 0))

			expect(editor) {
				#expect(!editor.model.textReplacementRequested("[", in: editor.model.selectedRange))
			} changes: {
				$0.state.displayedText = "[[]]"
				$0.state.isReferenceSuggestionSessionActive = true
				$0.state.selectedRange = NSRange(location: 2, length: 0)
				$0.contexts.append(.init(kind: .pageLink, query: "", fullText: "[[]]", cursorOffset: 2, queryRange: NSRange(location: 2, length: 0), tokenRange: NSRange(location: 0, length: 4)))
			}
		}

		// MARK: - Test Support

		private func storedParagraph() throws -> Paragraph {
			@Dependency(\.defaultDatabase) var database
			return try database.write { db in
				let page = try #require(try Page.insert { Page(title: "Page") }.returning(\.self).fetchOne(db))
				return try #require(try Paragraph.insert {
					Paragraph(id: UUID(100), string: "original", parentId: page.id, pageId: page.id, order: 0)
				}
				.returning(\.self)
				.fetchOne(db))
			}
		}

		private func nextMainQueueTurn() async {
			await withCheckedContinuation { continuation in
				DispatchQueue.main.async { continuation.resume() }
			}
		}
	}
}

/// Holds a model and a native text view without a window or an installed delegate.
/// Tests call model events or delegate methods explicitly; native text changes do not send those events.
@MainActor @DebugSnapshot
private final class Editor {
	@DebugSnapshotIgnored let model: EditableTextModel
	@DebugSnapshotTracked var state: EditableTextModel.DebugSnapshot {
		snap(model)
	}

	var openedURLs: [URL] = []
	var actions: [EditableText.Action] = []
	var commands: [ReferenceSuggestions.Command] = []
	var contexts: [ReferenceSuggestions.Context?] = []
	var onAction: (EditableText.Action) -> Bool = { _ in false }
	var onCommand: (ReferenceSuggestions.Command) -> Bool = { _ in false }

	@DebugSnapshotIgnored let textView = PlatformTextView()
	@DebugSnapshotIgnored let blockCoordinator = BlockCoordinator()
	@DebugSnapshotIgnored let coordinator: EditableTextView.Coordinator
	@DebugSnapshotTracked var activeBlockID: Block.ID? {
		blockCoordinator.activelyEditingBlock
	}

	init(_ originalText: String, editing: Bool = true, selection: NSRange = NSRange(location: 0, length: 0)) {
		model = withDependencies { [blockCoordinator] in
			$0.blockCoordinator = blockCoordinator
			#if os(iOS)
			$0.blockSelectionCoordinator = BlockSelectionCoordinator()
			#endif
		} operation: { EditableTextModel() }
		coordinator = EditableTextView.Coordinator(model: model)
		#if os(macOS)
		textView.isRichText = false
		#endif
		update(originalText)
		model.textViewAttached(textView)
		if editing {
			beginEditing()
		}
		model.selectedRange = selection
	}

	func update(_ originalText: String, fontSize: CGFloat = 13) {
		model.update(
			blockId: UUID(100), originalText: originalText, font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil) as PlatformFont,
			handleAction: { [unowned self] in actions.append($0); return onAction($0) },
			onLinkClicked: { [unowned self] in openedURLs.append($0) },
			onReferenceSuggestionCommand: { [unowned self] in commands.append($0); return onCommand($0) },
			onReferenceSuggestionContextChange: { [unowned self] context, _ in contexts.append(context) }
		)
	}

	func beginEditing() {
		#if os(iOS)
		coordinator.textViewDidBeginEditing(textView)
		coordinator.textViewDidChangeSelection(textView)
		#else
		coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
		#endif
	}

	/// Sets the raw text and selection directly, without sending an editing event.
	func setNativeText(_ text: String, selection: NSRange) {
		model.setText(.raw, text: text)
		model.selectedRange = selection
	}
}
