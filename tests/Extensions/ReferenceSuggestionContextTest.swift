import Testing
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/ReferenceSuggestionContext")
	struct ReferenceSuggestionContextTest {}
}

extension Tests.ReferenceSuggestionContextTest {
	@Test("detects empty page-link context")
	func detectsEmptyPageLinkContext() throws {
		let text = "[[]]"
		let context = try #require(referenceSuggestionContext(in: text, cursorOffset: 2))

		expectNoDifference(context.kind, .pageLink)
		expectNoDifference(context.query, "")
		expectNoDifference(context.queryRange, NSRange(location: 2, length: 0))
		expectNoDifference(context.tokenRange, NSRange(location: 0, length: 4))
	}

	@Test("detects page-link context while editing query")
	func detectsPageLinkContextWhileEditingQuery() throws {
		let text = "[[February]]"
		let context = try #require(referenceSuggestionContext(in: text, cursorOffset: 5))

		expectNoDifference(context.kind, .pageLink)
		expectNoDifference(context.query, "February")
		expectNoDifference(context.queryRange, NSRange(location: 2, length: 8))
		expectNoDifference(context.tokenRange, NSRange(location: 0, length: 12))
	}

	@Test("does not detect page-link context for unterminated reference")
	func doesNotDetectPageLinkContextForUnterminatedReference() {
		let text = "[[Unfinished"
		#expect(referenceSuggestionContext(in: text, cursorOffset: 7) == nil)
	}

	@Test("does not detect page-link context when cursor is after closing brackets")
	func doesNotDetectPageLinkContextWhenCursorIsAfterClosingBrackets() {
		let text = "[[Page]]"
		#expect(referenceSuggestionContext(in: text, cursorOffset: 8) == nil)
	}

	@Test("detects the double-bracket reference containing cursor when multiple exist")
	func detectsContainingDoubleBracketReferenceWhenMultipleExist() throws {
		let text = "[[First]] [[Second]]"
		let context = try #require(referenceSuggestionContext(in: text, cursorOffset: 15))

		expectNoDifference(context.kind, .pageLink)
		expectNoDifference(context.query, "Second")
		expectNoDifference(context.queryRange, NSRange(location: 12, length: 6))
		expectNoDifference(context.tokenRange, NSRange(location: 10, length: 10))
	}

	@Test("detects bracketed tag context")
	func detectsBracketedTagContext() throws {
		let text = "#[[Travel Notes]]"
		let context = try #require(referenceSuggestionContext(in: text, cursorOffset: 6))

		expectNoDifference(context.kind, .tagBracketed)
		expectNoDifference(context.query, "Travel Notes")
		expectNoDifference(context.queryRange, NSRange(location: 3, length: 12))
		expectNoDifference(context.tokenRange, NSRange(location: 0, length: 17))
	}

	@Test("detects simple tag context and stops at whitespace")
	func detectsSimpleTagContextAndStopsAtWhitespace() throws {
		let text = "#tag hello"
		let contextAtTag = try #require(referenceSuggestionContext(in: text, cursorOffset: 4))

		expectNoDifference(contextAtTag.kind, .tagSimple)
		expectNoDifference(contextAtTag.query, "tag")
		expectNoDifference(contextAtTag.queryRange, NSRange(location: 1, length: 3))
		expectNoDifference(contextAtTag.tokenRange, NSRange(location: 0, length: 4))

		#expect(referenceSuggestionContext(in: text, cursorOffset: 5) == nil)
	}

	@Test("simple tag context stops at invalid characters")
	func simpleTagContextStopsAtInvalidCharacters() throws {
		let text = "#todo!more"
		let contextAtBoundary = try #require(referenceSuggestionContext(in: text, cursorOffset: 5))

		expectNoDifference(contextAtBoundary.kind, .tagSimple)
		expectNoDifference(contextAtBoundary.query, "todo")
		expectNoDifference(contextAtBoundary.queryRange, NSRange(location: 1, length: 4))
		expectNoDifference(contextAtBoundary.tokenRange, NSRange(location: 0, length: 5))

		#expect(referenceSuggestionContext(in: text, cursorOffset: 6) == nil)
	}

	@Test("detects empty simple tag context for #")
	func detectsEmptySimpleTagContext() throws {
		let text = "#"
		let context = try #require(referenceSuggestionContext(in: text, cursorOffset: 1))

		expectNoDifference(context.kind, .tagSimple)
		expectNoDifference(context.query, "")
		expectNoDifference(context.queryRange, NSRange(location: 1, length: 0))
		expectNoDifference(context.tokenRange, NSRange(location: 0, length: 1))
	}

	@Test("replacement for page links leaves cursor after token")
	func replacementForPageLinksLeavesCursorAfterToken() throws {
		let context = try #require(referenceSuggestionContext(in: "[[Fe]]", cursorOffset: 4))
		let replaced = replacingReferenceSuggestion(
			in: context.fullText,
			context: context,
			with: "My Page"
		)

		expectNoDifference(replaced.text, "[[My Page]]")
		expectNoDifference(replaced.cursorOffsetAfterToken, 11)
	}

	@Test("replacement for simple tags uses #title when possible")
	func replacementForSimpleTagsUsesSimpleSyntax() throws {
		let context = try #require(referenceSuggestionContext(in: "#fe", cursorOffset: 3))
		let replaced = replacingReferenceSuggestion(
			in: context.fullText,
			context: context,
			with: "todo_1"
		)

		expectNoDifference(replaced.text, "#todo_1")
		expectNoDifference(replaced.cursorOffsetAfterToken, 7)
	}

	@Test("replacement for tags falls back to bracketed syntax for spaced titles")
	func replacementForTagsFallsBackToBracketedSyntaxForSpacedTitles() throws {
		let context = try #require(referenceSuggestionContext(in: "#tag", cursorOffset: 4))
		let replaced = replacingReferenceSuggestion(
			in: context.fullText,
			context: context,
			with: "my tag"
		)

		expectNoDifference(replaced.text, "#[[my tag]]")
		expectNoDifference(replaced.cursorOffsetAfterToken, 11)
	}
}

private func referenceSuggestionContext(in text: String, cursorOffset: Int) -> ReferenceSuggestions.Context? {
	ReferenceSuggestions.Context(in: text, cursorOffset: cursorOffset)
}

private func replacingReferenceSuggestion(
	in text: String,
	context: ReferenceSuggestions.Context,
	with suggestionTitle: String
) -> (text: String, cursorOffsetAfterToken: Int) {
	let replacementToken = switch context.kind {
		case .pageLink:
			"[[\(suggestionTitle)]]"
		case .tagSimple, .tagBracketed:
			TagSyntax.makeTagReference(for: suggestionTitle)
	}

	let updatedText = (text as NSString).replacingCharacters(in: context.tokenRange, with: replacementToken)
	let cursorOffsetAfterToken = context.tokenRange.location + replacementToken.utf16Length
	return (updatedText, cursorOffsetAfterToken)
}
