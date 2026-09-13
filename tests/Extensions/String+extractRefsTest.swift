import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/String+extractRefs")
	struct StringExtractRefsTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.StringExtractRefsTest {
	@Test("extractRefs finds page links, tags, and block refs in order")
	func extractRefsFindsAllKindsInOrder() {
		let uuidString = "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E"
		let text = "Intro [[Page One]] mid #tag and #[[On Plex]] then ((\(uuidString))) end"

		let refs = text.extractRefs()

		expectNoDifference(refs.map(\.kind), [.pageLink, .tag, .tag, .blockRef])
		expectNoDifference(refs.map(\.target), ["Page One", "tag", "On Plex", uuidString])
		expectNoDifference(refs.map { String(text[$0.range]) }, ["[[Page One]]", "#tag", "#[[On Plex]]", "((\(uuidString)))"])
	}

	@Test("Bracketed tags do not also produce page link refs")
	func bracketedTagsDoNotCreatePageLinks() {
		let text = "Tag #[[Megalopolis]] and [[Megalopolis]]"

		let refs = text.extractRefs()

		expectNoDifference(refs.map(\.kind), [.tag, .pageLink])
		expectNoDifference(refs.map(\.target), ["Megalopolis", "Megalopolis"])
		expectNoDifference(refs.map { String(text[$0.range]) }, ["#[[Megalopolis]]", "[[Megalopolis]]"])
	}

	@Test("extractRefs ignores whitespace-only references")
	func extractRefsIgnoresWhitespaceOnly() {
		let text = "Ignored [[   ]] #[[  \n\t ]] and more."

		let refs = text.extractRefs()
		#expect(refs.isEmpty)
	}

	@Test("extractRefs ignores page links with trimmed length under 3")
	func extractRefsIgnoresShortPageLinks() {
		let refs = "See [[AB ]] and [[AB]] text".extractRefs()
		#expect(refs.isEmpty)
	}

	@Test("extractRefs ignores bracketed tags with trimmed length under 3")
	func extractRefsIgnoresShortBracketedTags() {
		let refs = "Tag #[[AB ]] and #[[XY]] #XY here".extractRefs()
		#expect(refs.isEmpty)
	}

	@Test("extractRefs accepts references with trimmed length of exactly 3")
	func extractRefsAcceptsThreeCharReferences() {
		let refs = "Link [[ABC]] tag #[[DEF]] simple #GHI".extractRefs()
		expectNoDifference(refs.map(\.target), ["ABC", "DEF", "GHI"])
		expectNoDifference(refs.map(\.kind), [.pageLink, .tag, .tag])
	}

	@Test("extractRefs preserves duplicate references by range")
	func extractRefsPreservesDuplicateReferences() {
		let text = "Repeat [[Page]] and [[Page]] again"

		let refs = text.extractRefs()

		expectNoDifference(refs.map(\.target), ["Page", "Page"])
		expectNoDifference(refs.map(\.kind), [.pageLink, .pageLink])
		expectNoDifference(refs.map(\.range.description), ["7[utf8]..<15[utf8]", "20[utf8]..<28[utf8]"])
	}

	@Test("extractRefs ignores invalid block refs")
	func extractRefsIgnoresInvalidBlockRefs() {
		let valid = "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E"
		let invalid = "12345678-1234-1234-1234-12345678901-"
		let text = "Valid ((\(valid))) invalid ((\(invalid)))"

		let refs = text.extractRefs()

		expectNoDifference(refs.map(\.target), [valid])
		expectNoDifference(refs.map(\.kind), [.blockRef])
		expectNoDifference(refs.map { String(text[$0.range]) }, ["((\(valid)))"])
	}

	@Test("TextRef.url percent-encodes targets and uses the correct scheme")
	func textRefUrlEncodesTargets() throws {
		let uuidString = "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E"
		let text = "[[Page One]] #[[On Plex]] ((\(uuidString)))"

		let refs = text.extractRefs()

		let tagRef = try #require(refs.first { $0.kind == .tag })
		let pageRef = try #require(refs.first { $0.kind == .pageLink })
		let blockRef = try #require(refs.first { $0.kind == .blockRef })

		expectNoDifference(tagRef.url.absoluteString, "lattice://tag/On%20Plex")
		expectNoDifference(pageRef.url.absoluteString, "lattice://page/Page%20One")
		expectNoDifference(blockRef.url.absoluteString, "lattice://block/\(uuidString)")
	}

	@Test("TextRef.replacement returns correct syntax for each kind")
	func textRefReplacementSyntax() throws {
		let uuidString = "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E"
		let text = "[[Old]] #[[New]] ((\(uuidString)))"

		let refs = text.extractRefs()
		let pageRef = try #require(refs.first { $0.kind == .pageLink })
		let tagRef = try #require(refs.first { $0.kind == .tag })
		let blockRef = try #require(refs.first { $0.kind == .blockRef })

		#expect(blockRef.replacement(forRenamedPage: "Anything", in: text) == nil)
		expectNoDifference(tagRef.replacement(forRenamedPage: "NewTag", in: text), "#[[NewTag]]")
		expectNoDifference(tagRef.replacement(forRenamedPage: "Café", in: text), "#[[Café]]")
		expectNoDifference(tagRef.replacement(forRenamedPage: "On Plex", in: text), "#[[On Plex]]")
		expectNoDifference(pageRef.replacement(forRenamedPage: "New Title", in: text), "[[New Title]]")
	}

	@Test("Accepted titles retain their target in links and tags", arguments: ["ABC", "C# notes", "Plan (v2)", "Café", "Notes 👨‍👩‍👧‍👦"])
	func acceptedTitlesRoundTrip(title: String) throws {
		try Page.validateTitle(title)
		let texts = ["[[\(title)]]", "#[[\(title)]]", "[label]([[\(title)]])", "[label](#[[\(title)]])"]
		let refs = texts.flatMap { $0.extractRefs() }
		expectNoDifference(refs.map(\.target), Array(repeating: title, count: 4))
		expectNoDifference(refs.map(\.kind), [.pageLink, .tag, .pageLink, .tag])
	}

	@Test("extractRefs ignores references inside markdown link labels")
	func extractRefsIgnoresReferencesInsideMarkdownLinkLabels() {
		let text = "[go #tag](https://example.com) and [[Real Page]]"

		let refs = text.extractRefs()

		expectNoDifference(refs.map(\.kind), [.pageLink])
		expectNoDifference(refs.map(\.target), ["Real Page"])
	}

	@Test("extractRefs ignores references inside inline code spans")
	func extractRefsIgnoresReferencesInsideCodeSpans() {
		let text = "Before #tag `[[Not a link]]` `#fakeTag [[Page]] ((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E))` after [[Real Link]]"

		let refs = text.extractRefs()

		expectNoDifference(refs.map(\.kind), [.tag, .pageLink])
		expectNoDifference(refs.map(\.target), ["tag", "Real Link"])
	}
}
