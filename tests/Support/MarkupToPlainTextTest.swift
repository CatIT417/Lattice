import Testing
import Foundation
import CustomDump
import Dependencies
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@testable import LatticeDev

extension Tests {
	@Suite("Support/MarkupToPlainText")
	struct MarkupToPlainTextTest {}
}

extension Tests.MarkupToPlainTextTest {
	@Test("Plain text preserves reference positions", arguments: [
		("en_US", "Meet on February 12, 2026 with Alice."),
		("fr_FR", "Meet on 12 février 2026 with Alice."),
	])
	func referencePositions(localeIdentifier: String, expected: String) {
		let source = "Meet on [[2026-02-12]] with [[Alice]]."
		withDependencies {
			$0.locale = Locale(identifier: localeIdentifier)
		} operation: {
			expectNoDifference(renderPlainText(fromMarkup: source), expected)
			expectNoDifference(buildAttributedString(from: source).attributedString.string, expected)
		}
	}

	@Test("Plain text preserves labels and literal code", arguments: [
		("Meet on [Thursday]([[2026-02-12]]).", "Meet on Thursday."),
		("Use `[[2026-02-12]]` as an example.", "Use [[2026-02-12]] as an example."),
		("**Meet [[2026-02-12]]** and ==[[Alice]]==.", "Meet February 12, 2026 and Alice."),
		("#[[2026-02-12]] #2026-02-13", "#February 12, 2026 #February 13, 2026"),
		("[[2026-02-30]]", "2026-02-30"),
		("[**Read this**](https://example.com)", "Read this"),
		("Plain text.", "Plain text."),
		("{{[[TODO]]}} Meet [[2026-02-12]]", "Meet February 12, 2026"),
		("((A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E))", "A3D1F3BA-1F3A-4E4B-8F3C-3F6A8B9C0D1E"),
	])
	func labelsAndCode(source: String, expected: String) {
		expectNoDifference(renderPlainText(fromMarkup: source), expected)
		expectNoDifference(buildAttributedString(from: source.strippingTodoPrefix()).attributedString.string, expected)
	}

	@Test("Date labels keep cursor offsets within the raw reference", arguments: ["en_US", "fr_FR", "ja_JP", "ar_SA"])
	func dateLabelOffsets(localeIdentifier: String) throws {
		let source = "👨‍👩‍👧‍👦 [[2026-02-12]] café"
		let prefix = "👨‍👩‍👧‍👦 "
		let rawOffset = 4
		let locale = Locale(identifier: localeIdentifier)
		let (result, label) = withDependencies { $0.locale = locale } operation: {
			(
				buildAttributedString(from: source, rawStartOffset: rawOffset),
				DayOfYear(day: 12, month: 2, year: 2026).title
			)
		}
		let mapping = try #require(result.indexMapping)
		let labelStart = prefix.utf16.count
		let labelEnd = labelStart + label.utf16.count
		let rawStart = prefix.utf16.count + 2 + rawOffset
		let rawEnd = rawStart + 10

		expectNoDifference(mapping.rawIndex(fromRendered: labelStart), rawStart)
		expectNoDifference(mapping.rawIndex(fromRendered: labelEnd - 1), rawEnd)
		expectNoDifference(mapping.rawIndex(fromRendered: labelEnd), rawEnd + 2)
		expectNoDifference(mapping.rawIndex(fromRendered: result.attributedString.length), source.utf16.count + rawOffset)
		let offsets = (0...result.attributedString.length).map(mapping.rawIndex(fromRendered:))
		expectNoDifference(offsets, offsets.sorted())
		for offset in labelStart..<labelEnd {
			#expect((rawStart...rawEnd).contains(mapping.rawIndex(fromRendered: offset)))
		}
		let url = try #require(result.attributedString.attribute(.link, at: labelStart, effectiveRange: nil) as? URL)
		expectNoDifference(url.absoluteString, "lattice://page/2026-02-12")
	}
}
