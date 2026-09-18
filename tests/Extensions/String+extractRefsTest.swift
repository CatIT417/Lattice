import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/String+extractRefs")
	struct StringExtractRefsTest {
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

	@Test("Reference extraction rejects empty and short titles", arguments: [
		"Ignored [[   ]] #[[  \n\t ]] and more.",
		"See [[AB ]] and [[AB]] text",
		"Tag #[[AB ]] and #[[XY]] #XY here",
	])
	func rejectsInvalidReferenceTitles(text: String) {
		#expect(text.extractRefs().isEmpty)
	}

	@Test("extractRefs accepts references with trimmed length of exactly 3")
	func extractRefsAcceptsThreeCharReferences() {
		let refs = "Link [[ABC]] tag #[[DEF]] simple #GHI".extractRefs()
		expectNoDifference(refs.map(\.target), ["ABC", "DEF", "GHI"])
		expectNoDifference(refs.map(\.kind), [.pageLink, .tag, .tag])
	}

	@Test("extractRefs preserves duplicate references by range")
	func extractRefsPreservesDuplicateReferences() {
		let text = "🎉 Repeat [[Page]] and [[Page]] again"

		let refs = text.extractRefs()

		expectNoDifference(refs.map(\.target), ["Page", "Page"])
		expectNoDifference(refs.map(\.kind), [.pageLink, .pageLink])
		expectNoDifference(refs.map { NSRange($0.range, in: text) }, [NSRange(location: 10, length: 8), NSRange(location: 23, length: 8)])
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
		for title in ["Path/Title", "Percent%20Title", "Hash#Title"] {
			let ref = try #require("[[\(title)]]".extractRefs().first)
			let components = try #require(URLComponents(url: ref.url, resolvingAgainstBaseURL: false))
			expectNoDifference(components.scheme, "lattice")
			expectNoDifference(components.host, "page")
			expectNoDifference(components.path, "/\(title)")
			#expect(components.fragment == nil)
		}
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
}
