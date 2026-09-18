import Testing
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/ReferenceSuggestionContext")
	struct ReferenceSuggestionContextTest {}
}

extension Tests.ReferenceSuggestionContextTest {
	@Test("Bracketed references expose the full query and UTF-16 ranges", arguments: [
		("[[]]", 2, ReferenceSuggestions.Context.Kind.pageLink, "", NSRange(location: 2, length: 0), NSRange(location: 0, length: 4)),
		("[[February]]", 5, .pageLink, "February", NSRange(location: 2, length: 8), NSRange(location: 0, length: 12)),
		("#[[Travel Notes]]", 6, .tagBracketed, "Travel Notes", NSRange(location: 3, length: 12), NSRange(location: 0, length: 17)),
	])
	func bracketedContext(text: String, cursor: Int, kind: ReferenceSuggestions.Context.Kind, query: String, queryRange: NSRange, tokenRange: NSRange) throws {
		let context = try #require(referenceSuggestionContext(in: text, cursorOffset: cursor))
		expectNoDifference(context.kind, kind)
		expectNoDifference(context.query, query)
		expectNoDifference(context.queryRange, queryRange)
		expectNoDifference(context.tokenRange, tokenRange)
	}

	@Test("Incomplete references and positions after a token have no context", arguments: [
		("[[Unfinished", 7), ("[[Page]]", 8), ("#", 1),
	])
	func missingContext(text: String, cursor: Int) {
		#expect(referenceSuggestionContext(in: text, cursorOffset: cursor) == nil)
	}

	@Test("detects the double-bracket reference containing cursor when multiple exist")
	func detectsContainingDoubleBracketReferenceWhenMultipleExist() throws {
		let text = "[[First]] 🎉 [[Second]]"
		let context = try #require(referenceSuggestionContext(in: text, cursorOffset: 18))

		expectNoDifference(context.kind, .pageLink)
		expectNoDifference(context.query, "Second")
		expectNoDifference(context.queryRange, NSRange(location: 15, length: 6))
		expectNoDifference(context.tokenRange, NSRange(location: 13, length: 10))
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

	@Test("Page replacement preserves surrounding text and uses a UTF-16 cursor")
	func replacementForPageLinksLeavesCursorAfterToken() throws {
		let context = try #require(referenceSuggestionContext(in: "🎉 [[Fe]] suffix", cursorOffset: 7))
		let replaced = try context.replacing(with: "Café 🎉")
		expectNoDifference(replaced.text, "🎉 [[Café 🎉]] suffix")
		expectNoDifference(replaced.cursorOffsetAfterToken, 14)
	}

	@Test("Tag suggestions preserve their form and the following text", arguments: [
		("#old more text", "new", 4, "#new more text", 4),
		("#[[old]]suffix", "new", 6, "#[[new]]suffix", 8),
		("#[[old]] more text", "new", 6, "#[[new]] more text", 8),
		("#fe", "todo_1", 3, "#todo_1", 7),
		("#tag", "my tag", 4, "#[[my tag]]", 11),
	])
	func tagReplacementPreservesForm(text: String, replacement: String, cursor: Int, expected: String, expectedCursor: Int) throws {
		let context = try #require(ReferenceSuggestions.Context(in: text, cursorOffset: cursor))
		let replaced = try context.replacing(with: replacement)
		expectNoDifference(replaced.text, expected)
		expectNoDifference(replaced.cursorOffsetAfterToken, expectedCursor)
	}
}

private func referenceSuggestionContext(in text: String, cursorOffset: Int) -> ReferenceSuggestions.Context? {
	ReferenceSuggestions.Context(in: text, cursorOffset: cursorOffset)
}
