import Testing
import CustomDump
import Foundation
import InlineSnapshotTesting
import SnapshotTestingCustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Support/InlineParser")
	struct InlineParserTest {}
}

extension Tests.InlineParserTest {
	@Test("parse returns single text span for plain text")
	func parseReturnsTextSpanForPlainText() {
		let spans = InlineParser.default.parse("Hello world")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<11[utf8],
			    content: "Hello world",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects page links")
	func parseDetectsPageLinks() {
		let spans = InlineParser.default.parse("Hello [[World]]")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<6[utf8],
			    content: "Hello ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .pageLink,
			    range: 6[utf8]..<15[utf8],
			    content: "World",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects tags")
	func parseDetectsTags() {
		let spans = InlineParser.default.parse("Hello #tag")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<6[utf8],
			    content: "Hello ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .tag,
			    range: 6[utf8]..<10[utf8],
			    content: "tag",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects bracketed tags")
	func parseDetectsBracketedTags() {
		let spans = InlineParser.default.parse("Hello #[[tag with spaces]]")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<6[utf8],
			    content: "Hello ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .tag,
			    range: 6[utf8]..<26[utf8],
			    content: "tag with spaces",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects bold text")
	func parseDetectsBoldText() {
		let spans = InlineParser.default.parse("Hello **world**!")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<6[utf8],
			    content: "Hello ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .bold,
			    range: 6[utf8]..<15[utf8],
			    content: "world",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<5[utf8],
			        content: "world",
			        children: []
			      )
			    ]
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 15[utf8]..<16[utf8],
			    content: "!",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects italic text")
	func parseDetectsItalicText() {
		let spans = InlineParser.default.parse("Hello *world*!")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<6[utf8],
			    content: "Hello ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .italic,
			    range: 6[utf8]..<13[utf8],
			    content: "world",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<5[utf8],
			        content: "world",
			        children: []
			      )
			    ]
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 13[utf8]..<14[utf8],
			    content: "!",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects bold italic text as nested bold > italic")
	func parseDetectsBoldItalicText() throws {
		let spans = InlineParser.default.parse("Hello ***world***!")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<6[utf8],
			    content: "Hello ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .bold,
			    range: 6[utf8]..<17[utf8],
			    content: "*world*",
			    children: [
			      [0]: InlineSpan(
			        kind: .italic,
			        range: 0[any]..<7[utf8],
			        content: "world",
			        children: [
			          [0]: InlineSpan(
			            kind: .text,
			            range: 0[any]..<5[utf8],
			            content: "world",
			            children: []
			          )
			        ]
			      )
			    ]
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 17[utf8]..<18[utf8],
			    content: "!",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects inline code")
	func parseDetectsInlineCode() {
		let spans = InlineParser.default.parse("Use `code` here")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<4[utf8],
			    content: "Use ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .code,
			    range: 4[utf8]..<10[utf8],
			    content: "code",
			    children: []
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 10[utf8]..<15[utf8],
			    content: " here",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects highlight")
	func parseDetectsHighlight() {
		let spans = InlineParser.default.parse("This is ==highlighted== text")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<8[utf8],
			    content: "This is ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .highlight,
			    range: 8[utf8]..<23[utf8],
			    content: "highlighted",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<11[utf8],
			        content: "highlighted",
			        children: []
			      )
			    ]
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 23[utf8]..<28[utf8],
			    content: " text",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse detects links")
	func parseDetectsLinks() {
		let spans = InlineParser.default.parse("Visit [my site](https://example.com)")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<6[utf8],
			    content: "Visit ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .link(url: URL(https://example.com)),
			    range: 6[utf8]..<36[utf8],
			    content: "my site",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<7[utf8],
			        content: "my site",
			        children: []
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("code spans prevent reference parsing inside them")
	func codeSpansPreventReferenceParsing() {
		let spans = InlineParser.default.parse("`[[Not a link]]`")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .code,
			    range: 0[any]..<16[utf8],
			    content: "[[Not a link]]",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("code spans have highest priority")
	func codeSpansHaveHighestPriority() {
		let spans = InlineParser.default.parse("Text `**not bold** [[not link]]` more")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<5[utf8],
			    content: "Text ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .code,
			    range: 5[utf8]..<32[utf8],
			    content: "**not bold** [[not link]]",
			    children: []
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 32[utf8]..<37[utf8],
			    content: " more",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("bold can contain page links as children")
	func boldCanContainPageLinksAsChildren() {
		let spans = InlineParser.default.parse("**[[Page]]**")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .bold,
			    range: 0[any]..<12[utf8],
			    content: "[[Page]]",
			    children: [
			      [0]: InlineSpan(
			        kind: .pageLink,
			        range: 0[any]..<8[utf8],
			        content: "Page",
			        children: []
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("italic can contain tags as children")
	func italicCanContainTagsAsChildren() {
		let spans = InlineParser.default.parse("*hello #tag world*")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .italic,
			    range: 0[any]..<18[utf8],
			    content: "hello #tag world",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<6[utf8],
			        content: "hello ",
			        children: []
			      ),
			      [1]: InlineSpan(
			        kind: .tag,
			        range: 6[utf8]..<10[utf8],
			        content: "tag",
			        children: []
			      ),
			      [2]: InlineSpan(
			        kind: .text,
			        range: 10[utf8]..<16[utf8],
			        content: " world",
			        children: []
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("extractReferences returns refs from nested formatting")
	func extractReferencesReturnsRefsFromNestedFormatting() {
		let refs = InlineParser.default.extractReferences(from: "**[[Page]]** and *#tag*")

		assertInlineSnapshot(of: refs, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 2[utf8]..<10[utf8],
			    content: "Page",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .tag,
			    range: 18[utf8]..<22[utf8],
			    content: "tag",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("extractReferences ignores refs inside code")
	func extractReferencesIgnoresRefsInsideCode() {
		let refs = InlineParser.default.extractReferences(from: "`[[Not a ref]]` [[Real ref]]")

		assertInlineSnapshot(of: refs, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 16[utf8]..<28[utf8],
			    content: "Real ref",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("referencesOnly parser finds refs but ignores formatting")
	func referencesOnlyParserFindsRefsButIgnoresFormatting() {
		let refs = InlineParser.referencesOnly.extractReferences(from: "**[[Page]]** text")

		assertInlineSnapshot(of: refs, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 2[utf8]..<10[utf8],
			    content: "Page",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("tag rule has higher priority than page link for bracketed tags")
	func tagRuleHasHigherPriorityThanPageLink() {
		let spans = InlineParser.default.parse("#[[Tagged Page]]")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .tag,
			    range: 0[any]..<16[utf8],
			    content: "Tagged Page",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("block refs are detected")
	func blockRefsAreDetected() {
		let spans = InlineParser.default.parse("See ((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E))")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<4[utf8],
			    content: "See ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .blockRef,
			    range: 4[utf8]..<44[utf8],
			    content: "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("invalid block refs are not matched")
	func invalidBlockRefsAreNotMatched() {
		let spans = InlineParser.default.parse("See ((not-a-uuid))")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<18[utf8],
			    content: "See ((not-a-uuid))",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse handles markdown links with parentheses in URL")
	func parseHandlesMarkdownLinksWithParensInURL() {
		let text = "See [link](https://en.wikipedia.org/wiki/Rust_(programming_language)) end"
		let spans = InlineParser.default.parse(text)

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<4[utf8],
			    content: "See ",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .link(url: URL(https://en.wikipedia.org/wiki/Rust_(programming_language))),
			    range: 4[utf8]..<69[utf8],
			    content: "link",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<4[utf8],
			        content: "link",
			        children: []
			      )
			    ]
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 69[utf8]..<73[utf8],
			    content: " end",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse handles bold with nested italic closing at same boundary")
	func parseHandlesBoldWithNestedItalicClosingAtSameBoundary() throws {
		// **foo *bar*** — bold containing italic "bar" where italic's * and bold's ** are adjacent
		let spans = InlineParser.default.parse("**foo *bar***")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .bold,
			    range: 0[any]..<13[utf8],
			    content: "foo *bar*",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<4[utf8],
			        content: "foo ",
			        children: []
			      ),
			      [1]: InlineSpan(
			        kind: .italic,
			        range: 4[utf8]..<9[utf8],
			        content: "bar",
			        children: [
			          [0]: InlineSpan(
			            kind: .text,
			            range: 0[any]..<3[utf8],
			            content: "bar",
			            children: []
			          )
			        ]
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("markdown link takes priority over page link in ambiguous [[ sequences")
	func markdownLinkTakesPriorityOverPageLink() throws {
		// [[[hello](url) 😁]] — markdown link should win, not page link
		let spans = InlineParser.default.parse("[[[hello](http://example.com) 😁]]")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .link(url: URL(http://example.com)),
			    range: 0[any]..<29[utf8],
			    content: "[[hello",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<7[utf8],
			        content: "[[hello",
			        children: []
			      )
			    ]
			  ),
			  [1]: InlineSpan(
			    kind: .text,
			    range: 29[utf8]..<36[utf8],
			    content: " 😁]]",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("parse handles italic with nested bold closing at same boundary")
	func parseHandlesItalicWithNestedBoldClosingAtSameBoundary() throws {
		// *foo **bar*** — italic containing bold "bar" where bold's ** and italic's * are adjacent
		let spans = InlineParser.default.parse("*foo **bar***")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .italic,
			    range: 0[any]..<13[utf8],
			    content: "foo **bar**",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<4[utf8],
			        content: "foo ",
			        children: []
			      ),
			      [1]: InlineSpan(
			        kind: .bold,
			        range: 4[utf8]..<11[utf8],
			        content: "bar",
			        children: [
			          [0]: InlineSpan(
			            kind: .text,
			            range: 0[any]..<3[utf8],
			            content: "bar",
			            children: []
			          )
			        ]
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("referencesOnly parser ignores refs inside markdown link labels")
	func referencesOnlyParserIgnoresRefsInsideMarkdownLinkLabels() {
		let refs = InlineParser.referencesOnly.extractReferences(from: "[go #tag](https://example.com)")

		#expect(refs.isEmpty)
	}

	@Test("referencesOnly parser ignores block refs inside markdown link labels")
	func referencesOnlyParserIgnoresBlockRefsInsideMarkdownLinkLabels() {
		let refs = InlineParser.referencesOnly.extractReferences(from: "[see ((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E))](https://example.com)")

		#expect(refs.isEmpty)
	}

	@Test("markdown link label can contain page link syntax")
	func markdownLinkLabelCanContainPageLinkSyntax() throws {
		let spans = InlineParser.default.parse("[go [[Page]]](https://example.com)")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .link(url: URL(https://example.com)),
			    range: 0[any]..<34[utf8],
			    content: "go [[Page]]",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<11[utf8],
			        content: "go [[Page]]",
			        children: []
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("markdown link label can contain bracketed tag syntax")
	func markdownLinkLabelCanContainBracketedTagSyntax() throws {
		let spans = InlineParser.default.parse("[go #[[tag]]](https://example.com)")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .link(url: URL(https://example.com)),
			    range: 0[any]..<34[utf8],
			    content: "go #[[tag]]",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<11[utf8],
			        content: "go #[[tag]]",
			        children: []
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("referencesOnly ignores page links inside markdown labels with brackets")
	func referencesOnlyIgnoresPageLinksInsideMarkdownLabelsWithBrackets() {
		let refs = InlineParser.referencesOnly.extractReferences(from: "[go [[Page]]](https://example.com)")

		#expect(refs.isEmpty)
	}

	@Test("referencesOnly ignores bracketed tags inside markdown labels")
	func referencesOnlyIgnoresBracketedTagsInsideMarkdownLabels() {
		let refs = InlineParser.referencesOnly.extractReferences(from: "[go #[[tag]]](https://example.com)")

		#expect(refs.isEmpty)
	}

	@Test("markdown link rejects bare word URLs so wiki links are preserved")
	func markdownLinkRejectsBareWordURLs() {
		// [[Page]](todo) should be parsed as a page link, not a markdown link with URL "todo"
		let spans = InlineParser.default.parse("[[Page]](todo)")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 0[any]..<8[utf8],
			    content: "Page",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .text,
			    range: 8[utf8]..<14[utf8],
			    content: "(todo)",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("referencesOnly extracts page link when followed by parenthetical bare word")
	func referencesOnlyExtractsPageLinkFollowedByParentheticalBareWord() throws {
		let refs = InlineParser.referencesOnly.extractReferences(from: "[[Page]](todo)")

		assertInlineSnapshot(of: refs, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 0[any]..<8[utf8],
			    content: "Page",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("markdown link rejects schemeless colon URLs so wiki links are preserved")
	func markdownLinkRejectsSchemelessColonURLs() throws {
		// [[Page]](todo:urgent) should be parsed as page link + text, not a markdown link
		let spans = InlineParser.default.parse("[[Page]](todo:urgent)")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 0[any]..<8[utf8],
			    content: "Page",
			    children: []
			  ),
			  [1]: InlineSpan(
			    kind: .text,
			    range: 8[utf8]..<21[utf8],
			    content: "(todo:urgent)",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("underscore bold does not match when closing delimiter is intraword")
	func underscoreBoldDoesNotMatchIntrawordClosing() {
		// __init__value should not be parsed as bold "init"
		let spans = InlineParser.default.parse("__init__value")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<13[utf8],
			    content: "__init__value",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("underscore emphasis does not match when closing delimiter is intraword")
	func underscoreEmphasisDoesNotMatchIntrawordClosing() {
		// ___foo___bar should not be parsed as emphasis
		let spans = InlineParser.default.parse("___foo___bar")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .text,
			    range: 0[any]..<12[utf8],
			    content: "___foo___bar",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("extractReferences rebases nested reference ranges to original text")
	func extractReferencesRebasesNestedReferenceRanges() {
		let text = "**hello [[Page]]**"
		let refs = InlineParser.default.extractReferences(from: text)

		assertInlineSnapshot(of: refs, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 8[utf8]..<16[utf8],
			    content: "Page",
			    children: []
			  )
			]
			"""
		}

		guard let ref = refs.first else { Issue.record("Failed to extract reference"); return }

		// The range should be valid for slicing the original text
		expectNoDifference(String(text[ref.range]), "[[Page]]")
	}

	@Test("bold-italic correctly nests inner italic with same-char content")
	func boldItalicCorrectlyNestsInnerItalic() throws {
		let spans = InlineParser.default.parse("***foo *bar* baz***")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .bold,
			    range: 0[any]..<19[utf8],
			    content: "*foo *bar* baz*",
			    children: [
			      [0]: InlineSpan(
			        kind: .italic,
			        range: 0[any]..<15[utf8],
			        content: "foo *bar* baz",
			        children: [
			          [0]: InlineSpan(
			            kind: .text,
			            range: 0[any]..<4[utf8],
			            content: "foo ",
			            children: []
			          ),
			          [1]: InlineSpan(
			            kind: .italic,
			            range: 4[utf8]..<9[utf8],
			            content: "bar",
			            children: [
			              [0]: InlineSpan(
			                kind: .text,
			                range: 0[any]..<3[utf8],
			                content: "bar",
			                children: []
			              )
			            ]
			          ),
			          [2]: InlineSpan(
			            kind: .text,
			            range: 9[utf8]..<13[utf8],
			            content: " baz",
			            children: []
			          )
			        ]
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("italic with same-char nested italic produces correct nesting")
	func italicWithNestedSameCharItalic() throws {
		// *foo *bar* baz* — inner *bar* should nest inside outer italic
		let spans = InlineParser.default.parse("*foo *bar* baz*")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .italic,
			    range: 0[any]..<15[utf8],
			    content: "foo *bar* baz",
			    children: [
			      [0]: InlineSpan(
			        kind: .text,
			        range: 0[any]..<4[utf8],
			        content: "foo ",
			        children: []
			      ),
			      [1]: InlineSpan(
			        kind: .italic,
			        range: 4[utf8]..<9[utf8],
			        content: "bar",
			        children: [
			          [0]: InlineSpan(
			            kind: .text,
			            range: 0[any]..<3[utf8],
			            content: "bar",
			            children: []
			          )
			        ]
			      ),
			      [2]: InlineSpan(
			        kind: .text,
			        range: 9[utf8]..<13[utf8],
			        content: " baz",
			        children: []
			      )
			    ]
			  )
			]
			"""
		}
	}

	@Test("extractReferences rebases ranges correctly through bold-italic nesting")
	func extractReferencesRebasesRangesThroughBoldItalicNesting() {
		let text = "***hello [[Page]]***"
		let refs = InlineParser.default.extractReferences(from: text)

		assertInlineSnapshot(of: refs, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .pageLink,
			    range: 9[utf8]..<17[utf8],
			    content: "Page",
			    children: []
			  )
			]
			"""
		}

		guard let ref = refs.first else { Issue.record("Failed to extract reference"); return }

		expectNoDifference(String(text[ref.range]), "[[Page]]")
	}
}
