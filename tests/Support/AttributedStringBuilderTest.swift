import Testing
import CustomDump
import InlineSnapshotTesting
import SnapshotTestingCustomDump

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@testable import LatticeDev

extension Tests {
	@Suite("Support/AttributedStringBuilder")
	struct AttributedStringBuilderTest {}
}

private let testFont: PlatformFont = .systemFont(ofSize: 13)

extension Tests.AttributedStringBuilderTest {
	@Test("removeReferences strips link syntax for page links, tags, and block refs")
	func removeReferencesStripsLinkSyntax() {
		let uuid = UUID(uuidString: "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E")!
		let text = "Intro [[Page One]][[Second]] #tag #[[On Plex]] and ((\(uuid))) outro"
		let result = removeReferences(from: text)

		expectNoDifference(result, "Intro Page OneSecond tag On Plex and \(uuid) outro")
	}

	@Test("removeReferences returns the original string when there are no refs")
	func removeReferencesKeepsPlainText() {
		let text = "Just plain text."

		expectNoDifference(removeReferences(from: text), text)
	}

	@Test("buildAttributedString returns plain attributes when there are no refs")
	func buildAttributedStringNoRefs() {
		let text = "Plain text"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, text)
		#expect(result.indexMapping == nil)

		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Plain text{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
	}

	@Test("buildAttributedString renders links, colors, and index mappings for all ref kinds")
	func buildAttributedStringRendersLinksAndMapsOffsets() throws {
		let uuid = UUID(uuidString: "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E")!
		let text = "Start [[Page One]] middle #tag and #[[On Plex]] then ((\(uuid))) end."

		let result = buildAttributedString(from: text, font: testFont)
		let rendered = result.attributedString.string

		expectNoDifference(rendered, "Start Page One middle tag and On Plex then \(uuid) end.")
		let mapping = try #require(result.indexMapping)

		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Start {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}Page One{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://page/Page%20One";
			} middle {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}tag{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://tag/tag";
			} and {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}On Plex{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://tag/On%20Plex";
			} then {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://block/A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E";
			} end.{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}

		// ensure the rendered target characters map to the same characters inside the raw syntax

		var renderedSearchStart = rendered.startIndex
		for ref in text.extractRefs() {
			let rawRefText = String(text[ref.range])
			let rawTargetRange = rawRefText.range(of: ref.target)
			#expect(rawTargetRange != nil)

			let rawRefStart = text.distance(from: text.startIndex, to: ref.range.lowerBound)
			let rawTargetStart = rawRefText.distance(from: rawRefText.startIndex, to: rawTargetRange?.lowerBound ?? rawRefText.startIndex)
			let expectedRawStart = rawRefStart + rawTargetStart
			let expectedRawEnd = expectedRawStart + max(0, ref.target.count - 1)

			let renderedRange = rendered.range(of: ref.target, range: renderedSearchStart..<rendered.endIndex)
			#expect(renderedRange != nil)
			let renderedStart = rendered.distance(from: rendered.startIndex, to: renderedRange?.lowerBound ?? rendered.startIndex)
			let renderedEnd = rendered.distance(from: rendered.startIndex, to: renderedRange?.upperBound ?? rendered.startIndex) - 1
			renderedSearchStart = renderedRange?.upperBound ?? renderedSearchStart

			expectNoDifference(mapping.rawIndex(fromRendered: renderedEnd), expectedRawEnd)
			expectNoDifference(mapping.rawIndex(fromRendered: renderedStart), expectedRawStart)
		}

		expectNoDifference(mapping.rawIndex(fromRendered: -1), 0)
		expectNoDifference(mapping.rawIndex(fromRendered: rendered.count), text.count)
		expectNoDifference(mapping.rawIndex(fromRendered: rendered.count + 5), text.count)
	}
}
