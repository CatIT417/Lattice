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

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Plain text{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Plain text{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif
	}

	@Test("buildAttributedString renders links, colors, and index mappings for all ref kinds")
	func buildAttributedStringRendersLinksAndMapsOffsets() throws {
		let uuid = UUID(uuidString: "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E")!
		let text = "Start [[Page One]] middle #tag and #[[On Plex]] then ((\(uuid))) end."

		let result = buildAttributedString(from: text, font: testFont)
		let rendered = result.attributedString.string

		expectNoDifference(rendered, "Start Page One middle #tag and #On Plex then \(uuid) end.")
		let mapping = try #require(result.indexMapping)

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Start {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}Page One{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			    NSLink = "lattice://page/Page%20One";
			} middle {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}#tag{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			    NSLink = "lattice://tag/tag";
			} and {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}#On Plex{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			    NSLink = "lattice://tag/On%20Plex";
			} then {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			    NSLink = "lattice://block/A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E";
			} end.{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
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
			}#tag{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://tag/tag";
			} and {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}#On Plex{
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
		#endif

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

	@Test("buildAttributedString renders bold text")
	func buildAttributedStringRendersBoldText() throws {
		let text = "Hello **world**!"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Hello world!")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Hello {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}world{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			}!{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Hello {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}world{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			}!{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		var hasBoldTrait = false
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 6, length: 5)) { value, _, _ in
			if let font = value as? PlatformFont {
				#if canImport(UIKit)
				hasBoldTrait = font.fontDescriptor.symbolicTraits.contains(.traitBold)
				#else
				hasBoldTrait = font.fontDescriptor.symbolicTraits.contains(.bold)
				#endif
			}
		}
		#expect(hasBoldTrait)

		let mapping = try #require(result.indexMapping)
		// 'w' in rendered (index 6) should map to raw index 8 (after "Hello **")
		expectNoDifference(mapping.rawIndex(fromRendered: 6), 8)
	}

	@Test("buildAttributedString renders italic text")
	func buildAttributedStringRendersItalicText() throws {
		let text = "Hello *world*!"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Hello world!")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Hello {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}world{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-RegularItalic 13.00 pt. P [] () fobj=, spc=3.59\"";
			}!{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Hello {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}world{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-RegularItalic\"; font-weight: normal; font-style: italic; font-size: 13.00pt";
			}!{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		var hasItalicTrait = false
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 6, length: 5)) { value, _, _ in
			if let font = value as? PlatformFont {
				#if canImport(UIKit)
				hasItalicTrait = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
				#else
				hasItalicTrait = font.fontDescriptor.symbolicTraits.contains(.italic)
				#endif
			}
		}
		#expect(hasItalicTrait)

		let mapping = try #require(result.indexMapping)
		// 'w' in rendered (index 6) should map to raw index 7 (after "Hello *")
		expectNoDifference(mapping.rawIndex(fromRendered: 6), 7)
	}

	@Test("buildAttributedString renders inline code with monospace font")
	func buildAttributedStringRendersInlineCode() throws {
		let text = "Use `func foo()` here"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Use func foo() here")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Use {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}func foo(){
			    NSBackgroundColor = "Catalog color: System unemphasizedSelectedContentBackgroundColor";
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFontMonospaced-Regular 13.00 pt. P [] () fobj=, spc=8.04\"";
			} here{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Use {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}func foo(){
			    NSBackgroundColor = "<UIDynamicSystemColor; name = secondarySystemFillColor>";
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".AppleSystemUIFontMonospaced-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			} here{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif
	}

	@Test("buildAttributedString does not parse refs inside code spans")
	func buildAttributedStringDoesNotParseRefsInsideCode() throws {
		let text = "Link `[[Not a link]]` after"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Link [[Not a link]] after")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Link {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}[[Not a link]]{
			    NSBackgroundColor = "Catalog color: System unemphasizedSelectedContentBackgroundColor";
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFontMonospaced-Regular 13.00 pt. P [] () fobj=, spc=8.04\"";
			} after{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Link {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}[[Not a link]]{
			    NSBackgroundColor = "<UIDynamicSystemColor; name = secondarySystemFillColor>";
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".AppleSystemUIFontMonospaced-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			} after{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		var hasLink = false
		result.attributedString.enumerateAttribute(.link, in: NSRange(location: 0, length: result.attributedString.length)) { value, _, _ in
			if value != nil { hasLink = true }
		}
		#expect(!hasLink)
	}

	@Test("buildAttributedString renders highlight with yellow background")
	func buildAttributedStringRendersHighlight() throws {
		let text = "This is ==highlighted== text"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "This is highlighted text")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			This is {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}highlighted{
			    NSBackgroundColor = "sRGB IEC61966-2.1 colorspace hdrm(1) 1 0.839216 0 0.3";
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			} text{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			This is {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}highlighted{
			    NSBackgroundColor = "<UIDynamicModifiedColor; alpha = 0.3, baseColor = <UIDynamicCatalogSystemColor; name = systemYellowColor>>";
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			} text{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		// Check that highlighted portion has background color
		var hasBackgroundColor = false
		result.attributedString.enumerateAttribute(.backgroundColor, in: NSRange(location: 8, length: 11)) { value, _, _ in
			if value != nil { hasBackgroundColor = true }
		}
		#expect(hasBackgroundColor)
	}

	@Test("buildAttributedString renders markdown links")
	func buildAttributedStringRendersMarkdownLinks() throws {
		let text = "Visit [my site](https://example.com) today"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Visit my site today")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Visit {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}my site{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			    NSLink = "https://example.com";
			} today{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Visit {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}my site{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "https://example.com";
			} today{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		// Check that link has URL attribute
		var linkURL: URL?
		result.attributedString.enumerateAttribute(.link, in: NSRange(location: 6, length: 7)) { value, _, _ in
			linkURL = value as? URL
		}
		expectNoDifference(linkURL?.absoluteString, "https://example.com")
	}

	@Test("buildAttributedString handles nested bold and page link")
	func buildAttributedStringHandlesNestedBoldAndPageLink() throws {
		let text = "Check **[[Page]]** out"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Check Page out")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Check {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}Page{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			    NSLink = "lattice://page/Page";
			} out{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Check {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}Page{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://page/Page";
			} out{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		// Check that "Page" has both bold font and link attributes
		var foundBoldLink = false
		result.attributedString.enumerateAttributes(in: NSRange(location: 6, length: 4)) { attrs, _, _ in
			let font = attrs[.font] as? PlatformFont
			let link = attrs[.link] as? URL
			if font != nil, link != nil {
				#if canImport(UIKit)
				let isBold = font!.fontDescriptor.symbolicTraits.contains(.traitBold)
				#else
				let isBold = font!.fontDescriptor.symbolicTraits.contains(.bold)
				#endif
				foundBoldLink = isBold && link!.absoluteString == "lattice://page/Page"
			}
		}
		#expect(foundBoldLink)
	}

	@Test("buildAttributedString correctly maps cursor positions for markdown links")
	func buildAttributedStringCorrectlyMapsCursorPositionsForMarkdownLinks() throws {
		// Raw: "Visit [my site](https://example.com) today"
		//       0     6      14 15                35 36
		// The link text "my site" starts at raw index 7 (after "Visit [")
		// The ")" is at raw index 35, space is at 36, "today" starts at 37
		let text = "Visit [my site](https://example.com) today"
		let result = buildAttributedString(from: text, font: testFont)

		// Rendered: "Visit my site today"
		//           0     6     12 13
		// "my site" occupies rendered indices 6-12
		expectNoDifference(result.attributedString.string, "Visit my site today")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Visit {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}my site{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			    NSLink = "https://example.com";
			} today{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Visit {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}my site{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "https://example.com";
			} today{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		let mapping = try #require(result.indexMapping)

		// 'm' at rendered index 6 should map to raw index 7 (after "Visit [")
		expectNoDifference(mapping.rawIndex(fromRendered: 6), 7)
		// 'y' at rendered index 7 should map to raw index 8
		expectNoDifference(mapping.rawIndex(fromRendered: 7), 8)
		// 'e' at rendered index 12 (last char of "my site") should map to raw index 13
		expectNoDifference(mapping.rawIndex(fromRendered: 12), 13)
		// ' ' at rendered index 13 (after link) should map to raw index 36 (the space after ")")
		expectNoDifference(mapping.rawIndex(fromRendered: 13), 36)
		// 't' at rendered index 14 should map to raw index 37
		expectNoDifference(mapping.rawIndex(fromRendered: 14), 37)
	}

	@Test("buildAttributedString recurses into deeply nested formatted spans")
	func buildAttributedStringRecursesIntoDeeplyNestedFormattedSpans() throws {
		// **foo *[[Page]]* bar** should render bold "foo " + bold+italic link "Page" + bold " bar"
		// Raw:      **foo *[[Page]]* bar**
		// Indices:  01 234 5 67    1314 15 16   2021
		let text = "**foo *[[Page]]* bar**"
		let result = buildAttributedString(from: text, font: testFont)

		// Rendered should strip all delimiters
		expectNoDifference(result.attributedString.string, "foo Page bar")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			foo {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			}Page{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".SFNS-BoldItalic 13.00 pt. P [] () fobj=, spc=3.28\"";
			    NSLink = "lattice://page/Page";
			} bar{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			foo {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			}Page{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-SemiboldItalic\"; font-weight: bold; font-style: italic; font-size: 13.00pt";
			    NSLink = "lattice://page/Page";
			} bar{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		// "Page" (rendered indices 4-7) should have a link
		var linkURL: URL?
		result.attributedString.enumerateAttribute(.link, in: NSRange(location: 4, length: 4)) { value, _, _ in
			linkURL = value as? URL
		}
		expectNoDifference(linkURL?.absoluteString, "lattice://page/Page")

		// "Page" should have both bold and italic traits
		var hasBold = false
		var hasItalic = false
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 4, length: 4)) { value, _, _ in
			if let font = value as? PlatformFont {
				#if canImport(UIKit)
				hasBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
				#else
				hasBold = font.fontDescriptor.symbolicTraits.contains(.bold)
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
				#endif
			}
		}
		#expect(hasBold)
		#expect(hasItalic)

		// Cursor mappings
		let mapping = try #require(result.indexMapping)
		// 'f' at rendered 0 -> raw 2 (after **)
		expectNoDifference(mapping.rawIndex(fromRendered: 0), 2)
		// 'P' at rendered 4 -> raw 9 (after **foo *[[)
		expectNoDifference(mapping.rawIndex(fromRendered: 4), 9)
		// 'e' at rendered 7 -> raw 12
		expectNoDifference(mapping.rawIndex(fromRendered: 7), 12)
		// ' ' at rendered 8 -> raw 16 (after ]]*)
		expectNoDifference(mapping.rawIndex(fromRendered: 8), 16)
	}

	@Test("buildAttributedString does not parse intraword underscores as italic")
	func buildAttributedStringDoesNotParseIntrawordUnderscores() {
		let text = "foo_bar_baz"
		let result = buildAttributedString(from: text, font: testFont)

		// Should render as-is, underscores preserved
		expectNoDifference(result.attributedString.string, "foo_bar_baz")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			foo_bar_baz{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			foo_bar_baz{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif
	}

	@Test("buildAttributedString correctly maps cursor for formatted text inside markdown links")
	func buildAttributedStringCorrectlyMapsCursorForFormattedMarkdownLinks() throws {
		// Raw: "[**bold**](https://example.com)"
		//       0 12    78 9
		// Content "**bold**" is parsed as Bold(content: "bold")
		// Rendered: "bold" with link + bold
		let text = "[**bold**](https://example.com)"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "bold")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			bold{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			    NSLink = "https://example.com";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			bold{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			    NSLink = "https://example.com";
			}
			"""#
		}
		#endif

		// "bold" should have bold font trait
		var hasBold = false
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: 4)) { value, _, _ in
			if let font = value as? PlatformFont {
				#if canImport(UIKit)
				hasBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
				#else
				hasBold = font.fontDescriptor.symbolicTraits.contains(.bold)
				#endif
			}
		}
		#expect(hasBold)

		let mapping = try #require(result.indexMapping)
		// 'b' at rendered 0 -> raw 3 (after "[**")
		expectNoDifference(mapping.rawIndex(fromRendered: 0), 3)
		// 'o' at rendered 1 -> raw 4
		expectNoDifference(mapping.rawIndex(fromRendered: 1), 4)
		// 'd' at rendered 3 -> raw 6
		expectNoDifference(mapping.rawIndex(fromRendered: 3), 6)
	}

	@Test("buildAttributedString renders italic containing nested bold without leftover markers")
	func buildAttributedStringRendersItalicContainingNestedBold() throws {
		// *See **bold** text* — italic wrapping bold
		let text = "*See **bold** text*"
		let result = buildAttributedString(from: text, font: testFont)

		// Should render as "See bold text" with no leftover * characters
		expectNoDifference(result.attributedString.string, "See bold text")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			See {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-RegularItalic 13.00 pt. P [] () fobj=, spc=3.59\"";
			}bold{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-BoldItalic 13.00 pt. P [] () fobj=, spc=3.28\"";
			} text{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-RegularItalic 13.00 pt. P [] () fobj=, spc=3.59\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			See {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-RegularItalic\"; font-weight: normal; font-style: italic; font-size: 13.00pt";
			}bold{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-SemiboldItalic\"; font-weight: bold; font-style: italic; font-size: 13.00pt";
			} text{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-RegularItalic\"; font-weight: normal; font-style: italic; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		// "bold" (rendered 4-7) should have both italic and bold
		var hasBold = false
		var hasItalic = false
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 4, length: 4)) { value, _, _ in
			if let font = value as? PlatformFont {
				#if canImport(UIKit)
				hasBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
				#else
				hasBold = font.fontDescriptor.symbolicTraits.contains(.bold)
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
				#endif
			}
		}
		#expect(hasBold)
		#expect(hasItalic)
	}

	@Test("buildAttributedString renders bold containing nested bold-italic without leftover markers")
	func buildAttributedStringRendersBoldContainingNestedBoldItalic() throws {
		// **See ***both*** text** — bold wrapping bold-italic
		let text = "**See ***both*** text**"
		let result = buildAttributedString(from: text, font: testFont)

		// Should render as "See both text" with no leftover * characters
		expectNoDifference(result.attributedString.string, "See both text")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			See {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			}both{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-BoldItalic 13.00 pt. P [] () fobj=, spc=3.28\"";
			} text{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			See {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			}both{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-SemiboldItalic\"; font-weight: bold; font-style: italic; font-size: 13.00pt";
			} text{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		// "both" (rendered 4-7) should have both bold and italic
		var hasBold = false
		var hasItalic = false
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 4, length: 4)) { value, _, _ in
			if let font = value as? PlatformFont {
				#if canImport(UIKit)
				hasBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
				#else
				hasBold = font.fontDescriptor.symbolicTraits.contains(.bold)
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
				#endif
			}
		}
		#expect(hasBold)
		#expect(hasItalic)
	}

	@Test("buildAttributedString recurses into markdown link children inside formatting")
	func buildAttributedStringRecursesIntoMarkdownLinkChildrenInsideFormatting() throws {
		// **[italic *x*](https://example.com)** — link with italic child inside bold
		let text = "**[italic *x*](https://example.com)**"
		let result = buildAttributedString(from: text, font: testFont)

		// Should render "italic x" (italic delimiters stripped)
		expectNoDifference(result.attributedString.string, "italic x")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			italic {
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			    NSLink = "https://example.com";
			}x{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".SFNS-BoldItalic 13.00 pt. P [] () fobj=, spc=3.28\"";
			    NSLink = "https://example.com";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			italic {
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			    NSLink = "https://example.com";
			}x{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-SemiboldItalic\"; font-weight: bold; font-style: italic; font-size: 13.00pt";
			    NSLink = "https://example.com";
			}
			"""#
		}
		#endif

		// "x" at rendered index 7 should have italic trait
		var hasItalic = false
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 7, length: 1)) { value, _, _ in
			if let font = value as? PlatformFont {
				#if canImport(UIKit)
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
				#else
				hasItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
				#endif
			}
		}
		#expect(hasItalic)

		// All text should have link attribute
		var hasLink = false
		result.attributedString.enumerateAttribute(.link, in: NSRange(location: 0, length: result.attributedString.length)) { value, _, _ in
			if let url = value as? URL {
				hasLink = url.absoluteString == "https://example.com"
			}
		}
		#expect(hasLink)
	}

	@Test("buildAttributedString keeps markdown URL when link text contains reference-like syntax")
	func buildAttributedStringKeepsMarkdownURLForReferenceLabels() throws {
		// [go #tag](https://example.com) — references aren't parsed inside link text,
		// so #tag stays as plain text and the whole link points to example.com
		let text = "[go #tag](https://example.com)"
		let result = buildAttributedString(from: text, font: testFont)

		// Rendered: "go #tag" (no reference parsing inside link text)
		expectNoDifference(result.attributedString.string, "go #tag")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			go #tag{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			    NSLink = "https://example.com";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			go #tag{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			    NSLink = "https://example.com";
			}
			"""#
		}
		#endif

		// ALL link attributes should point to the markdown URL
		var allLinkURLs: [URL] = []
		result.attributedString.enumerateAttribute(.link, in: NSRange(location: 0, length: result.attributedString.length)) { value, _, _ in
			if let url = value as? URL {
				allLinkURLs.append(url)
			}
		}

		expectNoDifference(allLinkURLs, [URL(string: "https://example.com")!])
	}

	@Test("buildAttributedString renders nested tags with # prefix")
	func buildAttributedStringRendersNestedTagsWithPrefix() throws {
		// **#tag** — tag inside bold should render with # prefix
		let text = "**#tag**"
		let result = buildAttributedString(from: text, font: testFont)

		// Should include the # prefix, just like a top-level tag
		expectNoDifference(result.attributedString.string, "#tag")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			#tag{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			    NSLink = "lattice://tag/tag";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			#tag{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://tag/tag";
			}
			"""#
		}
		#endif

		// Should have a link attribute
		var hasLink = false
		result.attributedString.enumerateAttribute(.link, in: NSRange(location: 0, length: result.attributedString.length)) { value, _, _ in
			if value is URL { hasLink = true }
		}
		#expect(hasLink)
	}

	@Test("buildAttributedString maps cursor positions in UTF-16 when text contains emoji and references")
	func buildAttributedStringMapsUTF16WithEmoji() throws {
		// Raw: "Hello 🎉 [[World]]!"
		//       UTF-16 offsets:
		//       H=0 e=1 l=2 l=3 o=4 ' '=5 🎉=6,7 ' '=8 [=9 [=10 W=11 o=12 r=13 l=14 d=15 ]=16 ]=17 !=18  end=19
		// Rendered: "Hello 🎉 World!"
		//       H=0 e=1 l=2 l=3 o=4 ' '=5 🎉=6,7 ' '=8 W=9 o=10 r=11 l=12 d=13 !=14  end=15

		let text = "Hello 🎉 [[World]]!"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Hello 🎉 World!")

		let mapping = try #require(result.indexMapping)
		assertInlineSnapshot(of: mapping, as: .customDump) {
			"""
			AttributedStringResult.IndexMapping(
			  renderedToRaw: [
			    [0]: 0,
			    [1]: 1,
			    [2]: 2,
			    [3]: 3,
			    [4]: 4,
			    [5]: 5,
			    [6]: 6,
			    [7]: 7,
			    [8]: 8,
			    [9]: 11,
			    [10]: 12,
			    [11]: 13,
			    [12]: 14,
			    [13]: 15,
			    [14]: 18,
			    [15]: 19
			  ]
			)
			"""
		}

		// Before emoji: identity mapping
		expectNoDifference(mapping.rawIndex(fromRendered: 5), 5)
		// Emoji occupies two UTF-16 code units in both rendered and raw
		expectNoDifference(mapping.rawIndex(fromRendered: 6), 6)
		expectNoDifference(mapping.rawIndex(fromRendered: 7), 7)
		// Space after emoji
		expectNoDifference(mapping.rawIndex(fromRendered: 8), 8)
		// 'W' in rendered (UTF-16 pos 9) maps to raw UTF-16 pos 11 (after "[[")
		expectNoDifference(mapping.rawIndex(fromRendered: 9), 11)
		// 'd' at rendered 13 maps to raw 15
		expectNoDifference(mapping.rawIndex(fromRendered: 13), 15)
		// '!' at rendered 14 maps to raw 18 (after "]]")
		expectNoDifference(mapping.rawIndex(fromRendered: 14), 18)
		// End position (rendered UTF-16 length 15) maps to raw UTF-16 length 19
		expectNoDifference(mapping.rawIndex(fromRendered: 15), 19)
		// Verify these are UTF-16 counts, not Swift Character counts
		#expect(text.count == 18, "raw text has 18 Swift chars but 19 UTF-16 code units")
		#expect(text.utf16.count == 19)
		#expect(result.attributedString.string.utf16.count == 15)
	}

	@Test("buildAttributedString correctly maps cursor for bracketed tags inside formatting")
	func buildAttributedStringCorrectlyMapsCursorForBracketedTagsInsideFormatting() throws {
		// Raw: "Bold **#[[My Tag]]** end"
		//       0    56 8   12     1819 21
		// The bold content is "#[[My Tag]]" starting at raw index 7
		// The tag "#[[My Tag]]" has bracket offset 3 (for "#[["), prefix "#"
		// Rendered: "Bold #My Tag end" — prefix "#" maps to raw 7, "My Tag" maps to raw 10+
		let text = "Bold **#[[My Tag]]** end"
		let result = buildAttributedString(from: text, font: testFont)

		// Rendered: "Bold #My Tag end"
		//           0    56       12
		expectNoDifference(result.attributedString.string, "Bold #My Tag end")

		#if os(macOS)
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Bold {
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}#My Tag{
			    NSColor = "Catalog color: System systemBlueColor";
			    NSFont = "\".SFNS-Bold 13.00 pt. P [] () fobj=, spc=3.28\"";
			    NSLink = "lattice://tag/My%20Tag";
			} end{
			    NSColor = "Catalog color: System labelColor";
			    NSFont = "\".AppleSystemUIFont 13.00 pt. P [] () fobj=, spc=3.58\"";
			}
			"""#
		}
		#else
		assertInlineSnapshot(of: result.attributedString, as: .raw) {
			#"""
			Bold {
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}#My Tag{
			    NSColor = "<UITintColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Semibold\"; font-weight: bold; font-style: normal; font-size: 13.00pt";
			    NSLink = "lattice://tag/My%20Tag";
			} end{
			    NSColor = "<UIDynamicCatalogSystemColor; name = labelColor>";
			    NSFont = "<UICTFont> font-family: \".SFUI-Regular\"; font-weight: normal; font-style: normal; font-size: 13.00pt";
			}
			"""#
		}
		#endif

		let mapping = try #require(result.indexMapping)

		// '#' at rendered index 5 should map to raw index 7 (after "Bold **")
		expectNoDifference(mapping.rawIndex(fromRendered: 5), 7)
		// 'M' at rendered index 6 should map to raw index 10 (after "Bold **#[[")
		expectNoDifference(mapping.rawIndex(fromRendered: 6), 10)
		// 'y' at rendered index 7 should map to raw index 11
		expectNoDifference(mapping.rawIndex(fromRendered: 7), 11)
		// 'g' at rendered index 11 (last char of "My Tag") should map to raw index 15
		expectNoDifference(mapping.rawIndex(fromRendered: 11), 15)
	}

	@Test("buildAttributedString with rawStartOffset shifts index mapping for plain text")
	func buildAttributedStringWithRawStartOffsetPlainText() throws {
		// Plain text (no markup characters) — exercises the fast path in plainAttributedResult
		let text = "Plain text"
		let offset = 42
		let result = buildAttributedString(from: text, font: testFont, rawStartOffset: offset)

		expectNoDifference(result.attributedString.string, "Plain text")

		// With offset > 0, we should get an index mapping (unlike offset == 0 which returns nil)
		let mapping = try #require(result.indexMapping)

		// Each rendered position should map to itself + offset
		expectNoDifference(mapping.rawIndex(fromRendered: 0), offset)
		expectNoDifference(mapping.rawIndex(fromRendered: 5), 5 + offset)
		// End position
		expectNoDifference(mapping.rawIndex(fromRendered: text.utf16.count), text.utf16.count + offset)
	}

	@Test("buildAttributedString with rawStartOffset shifts index mapping when markup chars present but no valid syntax")
	func buildAttributedStringWithRawStartOffsetInvalidMarkup() throws {
		// Contains markup characters (*) but they don't form valid syntax — still takes the plain path
		let text = "A single * star"
		let offset = 10
		let result = buildAttributedString(from: text, font: testFont, rawStartOffset: offset)

		expectNoDifference(result.attributedString.string, "A single * star")

		let mapping = try #require(result.indexMapping)
		expectNoDifference(mapping.rawIndex(fromRendered: 0), offset)
		expectNoDifference(mapping.rawIndex(fromRendered: 9), 9 + offset)
		expectNoDifference(mapping.rawIndex(fromRendered: text.utf16.count), text.utf16.count + offset)
	}

	@Test("buildAttributedString with rawStartOffset shifts index mapping for formatted text")
	func buildAttributedStringWithRawStartOffsetFormatted() throws {
		// Text with actual formatting — exercises the main render path with offset
		// Raw: "Hello **world**!"
		//       0     67     1314 15
		// Rendered: "Hello world!"
		//           0     6     11
		let text = "Hello **world**!"
		let offset = 20
		let result = buildAttributedString(from: text, font: testFont, rawStartOffset: offset)

		expectNoDifference(result.attributedString.string, "Hello world!")

		let mapping = try #require(result.indexMapping)
		// 'H' at rendered 0 -> raw 0 + offset = 20
		expectNoDifference(mapping.rawIndex(fromRendered: 0), 0 + offset)
		// ' ' at rendered 5 -> raw 5 + offset = 25
		expectNoDifference(mapping.rawIndex(fromRendered: 5), 5 + offset)
		// 'w' at rendered 6 -> raw 8 + offset = 28 (after "Hello **")
		expectNoDifference(mapping.rawIndex(fromRendered: 6), 8 + offset)
		// 'd' at rendered 10 -> raw 12 + offset = 32
		expectNoDifference(mapping.rawIndex(fromRendered: 10), 12 + offset)
		// '!' at rendered 11 -> raw 15 + offset = 35 (after "**")
		expectNoDifference(mapping.rawIndex(fromRendered: 11), 15 + offset)
		// End position: rendered length 12 -> raw length 16 + offset = 36
		expectNoDifference(mapping.rawIndex(fromRendered: 12), 16 + offset)
	}

	@Test("buildAttributedString with rawStartOffset shifts index mapping for references")
	func buildAttributedStringWithRawStartOffsetReferences() throws {
		// Text with a page link — exercises reference rendering with offset
		// Raw: "Go [[Home]]!"
		//       01 234    910 11
		// Rendered: "Go Home!"
		//           01 2345 67
		let text = "Go [[Home]]!"
		let offset = 50
		let result = buildAttributedString(from: text, font: testFont, rawStartOffset: offset)

		expectNoDifference(result.attributedString.string, "Go Home!")

		let mapping = try #require(result.indexMapping)
		// 'G' at rendered 0 -> raw 0 + offset = 50
		expectNoDifference(mapping.rawIndex(fromRendered: 0), 0 + offset)
		// ' ' at rendered 2 -> raw 2 + offset = 52
		expectNoDifference(mapping.rawIndex(fromRendered: 2), 2 + offset)
		// 'H' at rendered 3 -> raw 5 + offset = 55 (after "Go [[")
		expectNoDifference(mapping.rawIndex(fromRendered: 3), 5 + offset)
		// 'e' at rendered 6 -> raw 8 + offset = 58
		expectNoDifference(mapping.rawIndex(fromRendered: 6), 8 + offset)
		// '!' at rendered 7 -> raw 11 + offset = 61 (after "]]")
		expectNoDifference(mapping.rawIndex(fromRendered: 7), 11 + offset)
		// End position
		expectNoDifference(mapping.rawIndex(fromRendered: 8), 12 + offset)
	}
}
