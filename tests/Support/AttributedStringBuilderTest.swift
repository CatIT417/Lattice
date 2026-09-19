import Testing
import CustomDump
import InlineSnapshotTesting

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

		let starts = [(rendered: 6, raw: 8, length: 8), (rendered: 23, raw: 27, length: 3), (rendered: 32, raw: 38, length: 7), (rendered: 45, raw: 55, length: 36)]
		for start in starts {
			expectNoDifference(mapping.rawIndex(fromRendered: start.rendered), start.raw)
			expectNoDifference(mapping.rawIndex(fromRendered: start.rendered + start.length - 1), start.raw + start.length - 1)
		}

		expectNoDifference(mapping.rawIndex(fromRendered: -1), 0)
		expectNoDifference(mapping.rawIndex(fromRendered: rendered.utf16.count), text.utf16.count)
		expectNoDifference(mapping.rawIndex(fromRendered: rendered.utf16.count + 5), text.utf16.count)

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
	}

	@Test("Formatting applies only to its text range", arguments: [("**", true, false, 8), ("*", false, true, 7)])
	func renderedStyle(marker: String, bold: Bool, italic: Bool, rawStart: Int) throws {
		let result = buildAttributedString(from: "Hello \(marker)world\(marker)!", font: testFont)
		expectNoDifference(result.attributedString.string, "Hello world!")
		try expectAttributes(result.attributedString, range: 0..<6)
		try expectAttributes(result.attributedString, range: 6..<11, bold: bold, italic: italic)
		try expectAttributes(result.attributedString, range: 11..<12)
		let mapping = try #require(result.indexMapping)
		expectNoDifference(mapping.rawIndex(fromRendered: 6), rawStart)
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
		try expectAttributes(result.attributedString, range: 0..<4)
		try expectAttributes(result.attributedString, range: 4..<14, monospaced: true, background: codeBackground)
		try expectAttributes(result.attributedString, range: 14..<19)

	}

	@Test("buildAttributedString does not parse refs inside code spans")
	func buildAttributedStringDoesNotParseRefsInsideCode() throws {
		let text = "Link `[[Not a link]]` after"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Link [[Not a link]] after")

		try expectAttributes(result.attributedString, range: 0..<5)
		try expectAttributes(result.attributedString, range: 5..<19, monospaced: true, background: codeBackground)
		try expectAttributes(result.attributedString, range: 19..<25)

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
		try expectAttributes(result.attributedString, range: 0..<8)
		try expectAttributes(result.attributedString, range: 8..<19, background: .systemYellow.withAlphaComponent(0.3))
		try expectAttributes(result.attributedString, range: 19..<24)

	}

	@Test("Nested references retain inherited styles and cursor offsets", arguments: [false, true])
	func nestedReferenceStyles(deep: Bool) throws {
		let text = deep ? "**foo *[[Page]]* bar**" : "Check **[[Page]]** out"
		let result = buildAttributedString(from: text, font: testFont)
		expectNoDifference(result.attributedString.string, deep ? "foo Page bar" : "Check Page out")
		let start = deep ? 4 : 6
		try expectAttributes(result.attributedString, range: 0..<start, bold: deep)
		try expectAttributes(result.attributedString, range: start..<(start + 4), bold: true, italic: deep, link: "lattice://page/Page")
		try expectAttributes(result.attributedString, range: (start + 4)..<result.attributedString.length, bold: deep)
		let mapping = try #require(result.indexMapping)
		if deep {
			expectNoDifference([0, 4, 7, 8].map { mapping.rawIndex(fromRendered: $0) }, [2, 9, 12, 16])
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
		} else {
			expectNoDifference(mapping.rawIndex(fromRendered: 6), 10)
		}
	}

	@Test("buildAttributedString correctly maps cursor positions for markdown links")
	func buildAttributedStringCorrectlyMapsCursorPositionsForMarkdownLinks() throws {
		let text = "Visit [my site](https://example.com) today"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "Visit my site today")

		try expectAttributes(result.attributedString, range: 0..<6)
		try expectAttributes(result.attributedString, range: 6..<13, link: "https://example.com")
		try expectAttributes(result.attributedString, range: 13..<19)

		let mapping = try #require(result.indexMapping)

		expectNoDifference(mapping.rawIndex(fromRendered: 6), 7)
		expectNoDifference(mapping.rawIndex(fromRendered: 7), 8)
		expectNoDifference(mapping.rawIndex(fromRendered: 12), 13)
		expectNoDifference(mapping.rawIndex(fromRendered: 13), 36)
		expectNoDifference(mapping.rawIndex(fromRendered: 14), 37)
	}

	@Test("buildAttributedString does not parse intraword underscores as italic")
	func buildAttributedStringDoesNotParseIntrawordUnderscores() throws {
		let text = "foo_bar_baz"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "foo_bar_baz")

		try expectAttributes(result.attributedString, range: 0..<11)

	}

	@Test("buildAttributedString correctly maps cursor for formatted text inside markdown links")
	func buildAttributedStringCorrectlyMapsCursorForFormattedMarkdownLinks() throws {
		let text = "[**bold**](https://example.com)"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "bold")

		try expectAttributes(result.attributedString, range: 0..<4, bold: true, link: "https://example.com")

		let mapping = try #require(result.indexMapping)
		expectNoDifference(mapping.rawIndex(fromRendered: 0), 3)
		expectNoDifference(mapping.rawIndex(fromRendered: 1), 4)
		expectNoDifference(mapping.rawIndex(fromRendered: 3), 6)
	}

	@Test("Nested styles preserve both traits without markers", arguments: [
		("*See **bold** text*", "See bold text", false, true),
		("**See ***both*** text**", "See both text", true, false),
	])
	func nestedStyles(text: String, expected: String, outerBold: Bool, outerItalic: Bool) throws {
		let result = buildAttributedString(from: text, font: testFont)
		expectNoDifference(result.attributedString.string, expected)
		try expectAttributes(result.attributedString, range: 0..<4, bold: outerBold, italic: outerItalic)
		try expectAttributes(result.attributedString, range: 4..<8, bold: true, italic: true)
		try expectAttributes(result.attributedString, range: 8..<13, bold: outerBold, italic: outerItalic)
	}

	@Test("buildAttributedString recurses into markdown link children inside formatting")
	func buildAttributedStringRecursesIntoMarkdownLinkChildrenInsideFormatting() throws {
		let text = "**[italic *x*](https://example.com)**"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "italic x")

		try expectAttributes(result.attributedString, range: 0..<7, bold: true, link: "https://example.com")
		try expectAttributes(result.attributedString, range: 7..<8, bold: true, italic: true, link: "https://example.com")

	}

	@Test("buildAttributedString keeps markdown URL when link text contains reference-like syntax")
	func buildAttributedStringKeepsMarkdownURLForReferenceLabels() throws {
		let text = "[go #tag](https://example.com)"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "go #tag")

		try expectAttributes(result.attributedString, range: 0..<7, link: "https://example.com")

	}

	@Test("Nested tags retain their prefix, URL, and cursor offsets", arguments: [
		("**#tag**", "#tag", 0, 4, "lattice://tag/tag", [0, 1, 3], [2, 3, 5]),
		("Bold **#[[My Tag]]** end", "Bold #My Tag end", 5, 12, "lattice://tag/My%20Tag", [5, 6, 7, 11], [7, 10, 11, 15]),
	])
	func nestedTags(text: String, expected: String, start: Int, end: Int, url: String, rendered: [Int], raw: [Int]) throws {
		let result = buildAttributedString(from: text, font: testFont)
		expectNoDifference(result.attributedString.string, expected)
		try expectAttributes(result.attributedString, range: 0..<start)
		try expectAttributes(result.attributedString, range: start..<end, bold: true, link: url)
		try expectAttributes(result.attributedString, range: end..<result.attributedString.length)
		let mapping = try #require(result.indexMapping)
		expectNoDifference(rendered.map { mapping.rawIndex(fromRendered: $0) }, raw)
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

		expectNoDifference((0...15).map { mapping.rawIndex(fromRendered: $0) }, [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14, 15, 18, 19])
		expectNoDifference(mapping.rawIndex(fromRendered: -1), 0)
		expectNoDifference(mapping.rawIndex(fromRendered: 100), 19)
		expectNoDifference(mapping.transform(range: NSRange(location: 9, length: 5), maxLength: 19), NSRange(location: 11, length: 7))
		expectNoDifference(mapping.transform(range: NSRange(location: 14, length: 5), maxLength: 18), NSRange(location: 18, length: 0))
	}

	@Test("buildAttributedString renders markdown link with internal page destination")
	func buildAttributedStringRendersMarkdownLinkWithInternalPageDestination() throws {
		let text = "[custom text]([[Page]])"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, "custom text")

		try expectAttributes(result.attributedString, range: 0..<11, link: "lattice://page/Page")

		let mapping = try #require(result.indexMapping)
		expectNoDifference(mapping.rawIndex(fromRendered: 0), 1)
		expectNoDifference(mapping.rawIndex(fromRendered: 7), 8)
		expectNoDifference(mapping.rawIndex(fromRendered: 10), 11)
		expectNoDifference(mapping.rawIndex(fromRendered: 11), 23)
	}

	@Test("Raw offsets apply to plain, invalid, formatted, and reference text", arguments: [
		("Plain text", "Plain text", 42, [0, 5, 10], [42, 47, 52]),
		("A single * star", "A single * star", 10, [0, 9, 15], [10, 19, 25]),
		("Hello **world**!", "Hello world!", 20, [0, 5, 6, 10, 11, 12], [20, 25, 28, 32, 35, 36]),
		("Go [[Home]]!", "Go Home!", 50, [0, 2, 3, 6, 7, 8], [50, 52, 55, 58, 61, 62]),
	])
	func rawStartOffset(text: String, expected: String, offset: Int, rendered: [Int], raw: [Int]) throws {
		let result = buildAttributedString(from: text, font: testFont, rawStartOffset: offset)
		expectNoDifference(result.attributedString.string, expected)
		let mapping = try #require(result.indexMapping)
		expectNoDifference(rendered.map { mapping.rawIndex(fromRendered: $0) }, raw)
	}

	@Test("buildAttributedString uses smaller font for embed links")
	func buildAttributedStringUsesSmallerFontForEmbedLinks() {
		let text = "https://x.com/user/status/123"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, text)

		// Embed links should not trigger favicon loading
		expectNoDifference(result.uncachedFaviconURLs, [])

		// Font should be 0.9x base size for embed links
		var fontSize: CGFloat?
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: result.attributedString.length)) { value, _, _ in
			fontSize = (value as? PlatformFont)?.pointSize
		}
		expectNoDifference(fontSize, testFont.pointSize * 0.9)

		// Should have a link attribute
		var hasLink = false
		result.attributedString.enumerateAttribute(.link, in: NSRange(location: 0, length: result.attributedString.length)) { value, _, _ in
			if value is URL { hasLink = true }
		}
		#expect(hasLink)
	}

	@Test("buildAttributedString requests favicon for non-embed external links")
	func buildAttributedStringRequestsFaviconForNonEmbedLinks() {
		let text = "https://example.com"
		let result = buildAttributedString(from: text, font: testFont)

		expectNoDifference(result.attributedString.string, text)

		// Non-embed external links should request favicon
		expectNoDifference(result.uncachedFaviconURLs, [URL(string: "https://www.google.com/s2/favicons?sz=64&domain=example.com")!])

		// Font should remain at base size (no 0.9x scaling)
		var fontSize: CGFloat?
		result.attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: result.attributedString.length)) { value, _, _ in
			fontSize = (value as? PlatformFont)?.pointSize
		}
		expectNoDifference(fontSize, testFont.pointSize)
	}
}

extension Tests.AttributedStringBuilderTest {
	@Test("A cached favicon adds two mapped UTF-16 positions")
	func cachedFavicon() throws {
		let image = PlatformImage()
		let url = try #require(URL(string: "https://example.com"))
		var requests: [URL] = []
		let result = buildAttributedString(from: "Go https://example.com", font: testFont, faviconProvider: {
			requests.append($0)
			return image
		})
		expectNoDifference(requests, [url])
		expectNoDifference(result.uncachedFaviconURLs, [])
		expectNoDifference(result.attributedString.string, "Go \u{FFFC} https://example.com")
		let attachment = try #require(result.attributedString.attribute(.attachment, at: 3, effectiveRange: nil) as? NSTextAttachment)
		#expect(attachment.image === image)
		expectNoDifference(result.attributedString.attribute(.link, at: 3, effectiveRange: nil) as? URL, url)
		expectNoDifference(result.attributedString.attribute(.link, at: 4, effectiveRange: nil) as? URL, url)
		let mapping = try #require(result.indexMapping)
		expectNoDifference((0...24).map { mapping.rawIndex(fromRendered: $0) }, [0, 1, 2, 3, 3, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22])
	}
}

private var codeBackground: PlatformColor {
	#if canImport(UIKit)
	.secondarySystemFill
	#else
	.unemphasizedSelectedContentBackgroundColor
	#endif
}

private func expectAttributes(
	_ text: NSAttributedString, range: Range<Int>, bold: Bool = false, italic: Bool = false,
	monospaced: Bool = false, link: String? = nil, background: PlatformColor? = nil
) throws {
	try #require(range.lowerBound >= 0 && range.upperBound <= text.length)
	for index in range {
		let attributes = text.attributes(at: index, effectiveRange: nil)
		let font = try #require(attributes[.font] as? PlatformFont)
		#if canImport(UIKit)
		let traits = font.fontDescriptor.symbolicTraits
		#expect(traits.contains(.traitBold) == bold, "UTF-16 position \(index)")
		#expect(traits.contains(.traitItalic) == italic, "UTF-16 position \(index)")
		#expect(traits.contains(.traitMonoSpace) == monospaced, "UTF-16 position \(index)")
		let foreground: PlatformColor = link == nil ? .label : .tintColor
		#else
		let traits = font.fontDescriptor.symbolicTraits
		#expect(traits.contains(.bold) == bold, "UTF-16 position \(index)")
		#expect(traits.contains(.italic) == italic, "UTF-16 position \(index)")
		#expect(traits.contains(.monoSpace) == monospaced, "UTF-16 position \(index)")
		let foreground: PlatformColor = link == nil ? .labelColor : .systemBlue
		#endif
		expectNoDifference(font.pointSize, testFont.pointSize)
		expectNoDifference(attributes[.foregroundColor] as? PlatformColor, foreground)
		expectNoDifference(attributes[.backgroundColor] as? PlatformColor, background)
		expectNoDifference((attributes[.link] as? URL)?.absoluteString, link)
	}
}
