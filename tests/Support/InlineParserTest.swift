import Testing
import CustomDump
import Foundation
import InlineSnapshotTesting
import SnapshotTestingCustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Support/InlineParser")
	struct InlineParserTest {
		struct Span: Equatable, Sendable {
			var kind: InlineSpan.Kind
			var range: Range<Int>
			var content: String
			var children: [Span] = []

			init(kind: InlineSpan.Kind, range: Range<Int>, content: String, children: [Span] = []) {
				self.kind = kind
				self.range = range
				self.content = content
				self.children = children
			}

			init(_ span: InlineSpan, in source: String) {
				let range = NSRange(span.range, in: source)
				self.init(kind: span.kind, range: range.location..<NSMaxRange(range), content: span.content,
				          children: span.children.map { Span($0, in: span.content) })
			}
		}
	}
}

extension Tests.InlineParserTest {
	@Test("Plain text preserves text and source ranges")
	func parseReturnsTextSpanForPlainText() {
		let text = "Hello world"
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, [.init(kind: .text, range: 0..<11, content: "Hello world")])
	}

	@Test("Reference tokens preserve text, structure, and source ranges", arguments: [
		("Hello [[World]]", [.init(kind: .text, range: 0..<6, content: "Hello "), .init(kind: .pageLink, range: 6..<15, content: "World")]),
		("Hello #tag", [.init(kind: .text, range: 0..<6, content: "Hello "), .init(kind: .tag, range: 6..<10, content: "tag")]),
		(
			"Hello #[[tag with spaces]]",
			[.init(kind: .text, range: 0..<6, content: "Hello "), .init(kind: .tag, range: 6..<26, content: "tag with spaces")]
		),
		(
			"See ((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E))",
			[
				.init(kind: .text, range: 0..<4, content: "See "),
				.init(kind: .blockRef, range: 4..<44, content: "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E")
			]
		),
	] as [(String, [Span])])
	func parseReference(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("Formatting tokens preserve text, structure, and source ranges", arguments: [
		(
			"Hello **world**!",
			[
				.init(kind: .text, range: 0..<6, content: "Hello "),
				.init(kind: .bold, range: 6..<15, content: "world", children: [.init(kind: .text, range: 0..<5, content: "world")]),
				.init(kind: .text, range: 15..<16, content: "!")
			]
		),
		(
			"Hello *world*!",
			[
				.init(kind: .text, range: 0..<6, content: "Hello "),
				.init(kind: .italic, range: 6..<13, content: "world", children: [.init(kind: .text, range: 0..<5, content: "world")]),
				.init(kind: .text, range: 13..<14, content: "!")
			]
		),
		(
			"Use `code` here",
			[
				.init(kind: .text, range: 0..<4, content: "Use "),
				.init(kind: .code, range: 4..<10, content: "code"),
				.init(kind: .text, range: 10..<15, content: " here")
			]
		),
		(
			"This is ==highlighted== text",
			[
				.init(kind: .text, range: 0..<8, content: "This is "),
				.init(
					kind: .highlight,
					range: 8..<23,
					content: "highlighted",
					children: [.init(kind: .text, range: 0..<11, content: "highlighted")]
				),
				.init(kind: .text, range: 23..<28, content: " text")
			]
		),
	] as [(String, [Span])])
	func parseFormat(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("Combined bold and italic preserve text and source ranges")
	func parseDetectsBoldItalicText() {
		let text = "Hello ***world***!"
		let spans = InlineParser.default.parse(text)
		expectNoDifference(
			spans.map { Span($0, in: text) },
			[
				.init(kind: .text, range: 0..<6, content: "Hello "),
				.init(
					kind: .bold,
					range: 6..<17,
					content: "*world*",
					children: [.init(
						kind: .italic,
						range: 0..<7,
						content: "world",
						children: [.init(kind: .text, range: 0..<5, content: "world")]
					)]
				),
				.init(kind: .text, range: 17..<18, content: "!")
			]
		)
	}

	@Test("Markdown links preserve text and source ranges")
	func parseDetectsLinks() {
		let text = "Visit [my site](https://example.com)"
		let spans = InlineParser.default.parse(text)
		expectNoDifference(
			spans.map { Span($0, in: text) },
			[
				.init(kind: .text, range: 0..<6, content: "Visit "),
				.init(
					kind: .link(url: URL(string: "https://example.com")!),
					range: 6..<36,
					content: "my site",
					children: [.init(kind: .text, range: 0..<7, content: "my site")]
				)
			]
		)
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

	@Test("Nested references preserve text, structure, and source ranges", arguments: [
		(
			"**[[Page]]**",
			[.init(kind: .bold, range: 0..<12, content: "[[Page]]", children: [.init(kind: .pageLink, range: 0..<8, content: "Page")])]
		),
		(
			"*hello #tag world*",
			[.init(
				kind: .italic,
				range: 0..<18,
				content: "hello #tag world",
				children: [
					.init(kind: .text, range: 0..<6, content: "hello "),
					.init(kind: .tag, range: 6..<10, content: "tag"),
					.init(kind: .text, range: 10..<16, content: " world")
				]
			)]
		),
	] as [(String, [Span])])
	func parseNestedRef(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("Both parser modes extract references inside formatting", arguments: [false, true])
	func nestedReferenceExtraction(referencesOnly: Bool) {
		let text = "**[[Page]]** and *#tag*"
		let parser = referencesOnly ? InlineParser.referencesOnly : .default
		let refs = parser.extractReferences(from: text)
		expectNoDifference(refs.map { Span($0, in: text) }, [
			.init(kind: .pageLink, range: 2..<10, content: "Page"),
			.init(kind: .tag, range: 18..<22, content: "tag"),
		])
		expectNoDifference(refs.map { String(text[$0.range]) }, ["[[Page]]", "#tag"])
	}

	@Test("Reference extraction ignores code in both parser modes", arguments: [false, true])
	func extractReferencesIgnoresRefsInsideCode(referencesOnly: Bool) {
		let parser = referencesOnly ? InlineParser.referencesOnly : .default
		let refs = parser.extractReferences(from: "`[[Not a ref]]` [[Real ref]]")

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
			    kind: .link(
			      url: URL(https://en.wikipedia.org/wiki/Rust_(programming_language)),
			      embed: nil
			    ),
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

	@Test("Adjacent closing delimiters preserve text, structure, and source ranges", arguments: [
		(
			"**foo *bar***",
			[.init(
				kind: .bold,
				range: 0..<13,
				content: "foo *bar*",
				children: [
					.init(kind: .text, range: 0..<4, content: "foo "),
					.init(kind: .italic, range: 4..<9, content: "bar", children: [.init(kind: .text, range: 0..<3, content: "bar")])
				]
			)]
		),
		(
			"*foo **bar***",
			[.init(
				kind: .italic,
				range: 0..<13,
				content: "foo **bar**",
				children: [
					.init(kind: .text, range: 0..<4, content: "foo "),
					.init(kind: .bold, range: 4..<11, content: "bar", children: [.init(kind: .text, range: 0..<3, content: "bar")])
				]
			)]
		),
	] as [(String, [Span])])
	func parseAdjacentClose(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("markdown link takes priority over page link in ambiguous [[ sequences")
	func markdownLinkTakesPriorityOverPageLink() throws {
		// The first bracket opens the link. The next two brackets belong to its label.
		let spans = InlineParser.default.parse("[[[hello](http://example.com) 😁]]")

		assertInlineSnapshot(of: spans, as: .customDump) {
			"""
			[
			  [0]: InlineSpan(
			    kind: .link(
			      url: URL(http://example.com),
			      embed: nil
			    ),
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

	@Test("Markdown labels keep reference syntax literal", arguments: [
		"go #tag", "see ((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E))", "go [[Page]]", "go #[[tag]]",
	])
	func literalReferenceLabels(label: String) throws {
		let text = "[\(label)](https://example.com)"
		let url = try #require(URL(string: "https://example.com"))
		expectNoDifference(InlineParser.default.parse(text).map { Span($0, in: text) }, [
			.init(kind: .link(url: url), range: 0..<text.utf16.count, content: label, children: [
				.init(kind: .text, range: 0..<label.utf16.count, content: label),
			]),
		])
		#expect(InlineParser.referencesOnly.extractReferences(from: text).isEmpty)
	}

	@Test("Invalid Markdown destinations preserve page references", arguments: ["todo", "todo:urgent"])
	func invalidDestinations(destination: String) {
		let text = "[[Page]](\(destination))"
		let reference = Span(kind: .pageLink, range: 0..<8, content: "Page")
		expectNoDifference(InlineParser.default.parse(text).map { Span($0, in: text) }, [
			reference, .init(kind: .text, range: 8..<text.utf16.count, content: "(\(destination))"),
		])
		expectNoDifference(InlineParser.referencesOnly.extractReferences(from: text).map { Span($0, in: text) }, [reference])
	}

	@Test("Underscores inside words preserve text, structure, and source ranges", arguments: [
		("__init__value", [.init(kind: .text, range: 0..<13, content: "__init__value")]),
		("___foo___bar", [.init(kind: .text, range: 0..<12, content: "___foo___bar")]),
	] as [(String, [Span])])
	func parseUnderscore(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("Repeated nested styles preserve text, structure, and source ranges", arguments: [
		(
			"***foo *bar* baz***",
			[.init(
				kind: .bold,
				range: 0..<19,
				content: "*foo *bar* baz*",
				children: [.init(
					kind: .italic,
					range: 0..<15,
					content: "foo *bar* baz",
					children: [
						.init(kind: .text, range: 0..<4, content: "foo "),
						.init(kind: .italic, range: 4..<9, content: "bar", children: [.init(kind: .text, range: 0..<3, content: "bar")]),
						.init(kind: .text, range: 9..<13, content: " baz")
					]
				)]
			)]
		),
		(
			"*foo *bar* baz*",
			[.init(
				kind: .italic,
				range: 0..<15,
				content: "foo *bar* baz",
				children: [
					.init(kind: .text, range: 0..<4, content: "foo "),
					.init(kind: .italic, range: 4..<9, content: "bar", children: [.init(kind: .text, range: 0..<3, content: "bar")]),
					.init(kind: .text, range: 9..<13, content: " baz")
				]
			)]
		),
	] as [(String, [Span])])
	func parseSameStyleNesting(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("Internal Markdown destinations preserve text, structure, and source ranges", arguments: [
		(
			"[custom text]([[My Page]])",
			[.init(
				kind: .link(url: URL(string: "lattice://page/My%20Page")!),
				range: 0..<26,
				content: "custom text",
				children: [.init(kind: .text, range: 0..<11, content: "custom text")]
			)]
		),
		(
			"[see this](((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E)))",
			[.init(
				kind: .link(url: URL(string: "lattice://block/A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E")!),
				range: 0..<52,
				content: "see this",
				children: [.init(kind: .text, range: 0..<8, content: "see this")]
			)]
		),
		(
			"[click here](#mytag)",
			[.init(
				kind: .link(url: URL(string: "lattice://tag/mytag")!),
				range: 0..<20,
				content: "click here",
				children: [.init(kind: .text, range: 0..<10, content: "click here")]
			)]
		),
		(
			"[click here](#[[tag with spaces]])",
			[.init(
				kind: .link(url: URL(string: "lattice://tag/tag%20with%20spaces")!),
				range: 0..<34,
				content: "click here",
				children: [.init(kind: .text, range: 0..<10, content: "click here")]
			)]
		),
	] as [(String, [Span])])
	func parseInternalLink(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("Internal destinations expose their reference range", arguments: [
		("[[My Page]]", InlineSpan.Kind.pageLink, "My Page"),
		("#mytag", .tag, "mytag"),
		("#[[tag with spaces]]", .tag, "tag with spaces"),
		("((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E))", .blockRef, "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E"),
	])
	func internalReferenceRanges(destination: String, kind: InlineSpan.Kind, target: String) {
		let text = "[label](\(destination))"
		let refs = InlineParser.referencesOnly.extractReferences(from: text)
		expectNoDifference(refs.map { Span($0, in: text) }, [
			.init(kind: kind, range: 8..<(8 + destination.utf16.count), content: target),
		])
		expectNoDifference(refs.map { String(text[$0.range]) }, [destination])
	}

	@Test("Empty internal destinations remain literal text", arguments: ["[label]([[   ]])", "[label](#[[   ]])"])
	func emptyInternalDestinations(text: String) {
		expectNoDifference(InlineParser.default.parse(text).map { Span($0, in: text) }, [
			.init(kind: .text, range: 0..<text.utf16.count, content: text),
		])
		#expect(InlineParser.referencesOnly.extractReferences(from: text).isEmpty)
	}

	@Test("extractReferences preserves percent-literal page title from internal-destination link")
	func extractReferencesPreservesPercentLiteralPageTitle() {
		// Title contains a literal "A%2FB" — should NOT be decoded to "A/B"
		let text = #"[link]([[A%2FB]])"#
		let refs = InlineParser.referencesOnly.extractReferences(from: text)

		guard let ref = refs.first else { Issue.record("Failed to extract reference"); return }
		expectNoDifference(ref.content, "A%2FB")
		expectNoDifference(String(text[ref.range]), "[[A%2FB]]")
	}

	// MARK: - URL Detection

	@Test("Bare URLs preserve text, structure, and source ranges", arguments: [
		(
			"Visit https://example.com today",
			[
				.init(kind: .text, range: 0..<6, content: "Visit "),
				.init(kind: .link(url: URL(string: "https://example.com")!), range: 6..<25, content: "https://example.com"),
				.init(kind: .text, range: 25..<31, content: " today")
			]
		),
		(
			"Visit http://example.com today",
			[
				.init(kind: .text, range: 0..<6, content: "Visit "),
				.init(kind: .link(url: URL(string: "http://example.com")!), range: 6..<24, content: "http://example.com"),
				.init(kind: .text, range: 24..<30, content: " today")
			]
		),
		(
			"See https://example.com/path?q=1&r=2 for details",
			[
				.init(kind: .text, range: 0..<4, content: "See "),
				.init(
					kind: .link(url: URL(string: "https://example.com/path?q=1&r=2")!),
					range: 4..<36,
					content: "https://example.com/path?q=1&r=2"
				),
				.init(kind: .text, range: 36..<48, content: " for details")
			]
		),
		(
			"Go to https://example.com.",
			[
				.init(kind: .text, range: 0..<6, content: "Go to "),
				.init(kind: .link(url: URL(string: "https://example.com")!), range: 6..<25, content: "https://example.com"),
				.init(kind: .text, range: 25..<26, content: ".")
			]
		),
		(
			"(see https://example.com)",
			[
				.init(kind: .text, range: 0..<5, content: "(see "),
				.init(kind: .link(url: URL(string: "https://example.com")!), range: 5..<24, content: "https://example.com"),
				.init(kind: .text, range: 24..<25, content: ")")
			]
		),
		(
			"See https://en.wikipedia.org/wiki/Function_(mathematics) for info",
			[
				.init(kind: .text, range: 0..<4, content: "See "),
				.init(
					kind: .link(url: URL(string: "https://en.wikipedia.org/wiki/Function_(mathematics)")!),
					range: 4..<56,
					content: "https://en.wikipedia.org/wiki/Function_(mathematics)"
				),
				.init(kind: .text, range: 56..<65, content: " for info")
			]
		),
		(
			"(see https://en.wikipedia.org/wiki/Function_(mathematics))",
			[
				.init(kind: .text, range: 0..<5, content: "(see "),
				.init(
					kind: .link(url: URL(string: "https://en.wikipedia.org/wiki/Function_(mathematics)")!),
					range: 5..<57,
					content: "https://en.wikipedia.org/wiki/Function_(mathematics)"
				),
				.init(kind: .text, range: 57..<58, content: ")")
			]
		),
		(
			"Visit HTTPS://EXAMPLE.COM today",
			[
				.init(kind: .text, range: 0..<6, content: "Visit "),
				.init(kind: .link(url: URL(string: "HTTPS://EXAMPLE.COM")!), range: 6..<25, content: "HTTPS://EXAMPLE.COM"),
				.init(kind: .text, range: 25..<31, content: " today")
			]
		),
		(
			"Visit http://[2001:db8::1]/path today",
			[
				.init(kind: .text, range: 0..<6, content: "Visit "),
				.init(kind: .link(url: URL(string: "http://[2001:db8::1]/path")!), range: 6..<31, content: "http://[2001:db8::1]/path"),
				.init(kind: .text, range: 31..<37, content: " today")
			]
		),
		(
			"See https://example.com/search?filters[]=done end",
			[
				.init(kind: .text, range: 0..<4, content: "See "),
				.init(
					kind: .link(url: URL(string: "https://example.com/search?filters%5B%5D=done")!),
					range: 4..<45,
					content: "https://example.com/search?filters[]=done"
				),
				.init(kind: .text, range: 45..<49, content: " end")
			]
		),
	] as [(String, [Span])])
	func parseUrl(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("Multiple URLs preserve text and source ranges")
	func parseDetectsMultipleURLs() {
		let text = "https://a.com and https://b.com"
		let spans = InlineParser.default.parse(text)
		expectNoDifference(
			spans.map { Span($0, in: text) },
			[
				.init(kind: .link(url: URL(string: "https://a.com")!), range: 0..<13, content: "https://a.com"),
				.init(kind: .text, range: 13..<18, content: " and "),
				.init(kind: .link(url: URL(string: "https://b.com")!), range: 18..<31, content: "https://b.com")
			]
		)
	}

	@Test(
		"URL fragments do not create tags",
		arguments: ["Check https://example.com/#about for info", "Check HTTPS://example.com/#about for info"]
	)
	func urlFragments(text: String) {
		#expect(InlineParser.referencesOnly.extractReferences(from: text).isEmpty)
	}

	@Test("parse rejects scheme-only URL")
	func parseRejectsSchemeOnlyURL() {
		let spans = InlineParser.default.parse("Use http://, not ftp://")

		// "http://" alone should not become a link
		let hasLink = spans.contains { if case .link = $0.kind { true } else { false } }
		#expect(!hasLink)
		expectNoDifference(spans.map(\.content).joined(), "Use http://, not ftp://")
	}

	@Test("parse attaches embed info to embeddable URLs")
	func parseAttachesEmbedInfoToEmbeddableURLs() {
		let spans = InlineParser.default.parse("Visit https://x.com/user/status/123 today")

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
			    kind: .link(
			      url: URL(https://x.com/user/status/123),
			      embed: .tweet(url: URL(https://x.com/user/status/123))
			    ),
			    range: 6[utf8]..<35[utf8],
			    content: "https://x.com/user/status/123",
			    children: []
			  ),
			  [2]: InlineSpan(
			    kind: .text,
			    range: 35[utf8]..<41[utf8],
			    content: " today",
			    children: []
			  )
			]
			"""
		}
	}

	@Test("Nested reference ranges use the original UTF-16 source")
	func extractReferencesRebasesRangesThroughBoldItalicNesting() {
		let text = "🎉 ***hello [[Page]]***"
		let refs = InlineParser.default.extractReferences(from: text)
		expectNoDifference(refs.map { Span($0, in: text) }, [.init(kind: .pageLink, range: 12..<20, content: "Page")])
		expectNoDifference(refs.map { String(text[$0.range]) }, ["[[Page]]"])
	}

	@Test("Short references preserve text, structure, and source ranges", arguments: [
		("See [[AB ]] here", [.init(kind: .text, range: 0..<16, content: "See [[AB ]] here")]),
		("See #[[AB ]] here", [.init(kind: .text, range: 0..<17, content: "See #[[AB ]] here")]),
	] as [(String, [Span])])
	func parseShortReference(text: String, expected: [Span]) {
		let spans = InlineParser.default.parse(text)
		expectNoDifference(spans.map { Span($0, in: text) }, expected)
	}

	@Test("escaped delimiter inside emphasis is skipped, closer after it still matches")
	func escapedDelimiterInsideEmphasisIsSkipped() throws {
		let spans = InlineParser.default.parse(#"*foo \* bar*"#)

		expectNoDifference(1, spans.count)
		let italic = try #require(spans.first)
		expectNoDifference(.italic, italic.kind)
		expectNoDifference(#"foo \* bar"#, italic.content)
	}

	@Test("escaped delimiter does not close emphasis")
	func escapedDelimiterDoesNotCloseEmphasis() throws {
		let spans = InlineParser.default.parse(#"*foo\*"#)

		expectNoDifference(1, spans.count)
		expectNoDifference(.text, try #require(spans.first).kind)
		expectNoDifference(spans.map(\.content).joined(), #"*foo\*"#)
	}

	@Test("unclosed openers stay plain text and only the innermost opener pairs with the closer")
	func unclosedOpenersStayPlainText() throws {
		let spans = InlineParser.default.parse("a *b *c *d end*")

		try #require(spans.count == 2)
		expectNoDifference(.text, spans[0].kind)
		expectNoDifference("a *b *c ", spans[0].content)
		expectNoDifference(.italic, spans[1].kind)
		expectNoDifference("d end", spans[1].content)
	}
}
