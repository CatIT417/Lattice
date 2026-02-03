import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Maps character positions between rendered text (with links like "World") and raw text (with "[[World]]")
struct IndexMapping {
	fileprivate let renderedToRaw: [Int]

	/// Convert a cursor position from rendered text to raw text position
	func rawIndex(fromRendered renderedIndex: Int) -> Int {
		guard renderedIndex >= 0 else { return 0 }
		guard renderedIndex < renderedToRaw.count else {
			return renderedToRaw.last ?? renderedIndex
		}
		return renderedToRaw[renderedIndex]
	}
}

/// Result of building an attributed string, including the string and index mapping
struct AttributedStringResult {
	let indexMapping: IndexMapping?
	let attributedString: NSAttributedString
}

func removeReferences(from text: String) -> String {
	var result = text
	let refs = text.extractRefs().sorted { $0.range.lowerBound > $1.range.lowerBound }

	for ref in refs {
		result.replaceSubrange(ref.range, with: ref.target)
	}

	return result
}

/// Build an NSAttributedString from text with refs
func buildAttributedString(from text: String, font: PlatformFont = .preferredFont(forTextStyle: .body)) -> AttributedStringResult {
	let baseAttributes: [NSAttributedString.Key: Any] = [
		.font: font,
		.foregroundColor: labelColor,
	]

	let refs = text.extractRefs().sorted { $0.range.lowerBound < $1.range.lowerBound }
	if refs.isEmpty {
		return AttributedStringResult(indexMapping: nil, attributedString: NSAttributedString(string: text, attributes: baseAttributes))
	}

	let result = NSMutableAttributedString()
	var currentIndex = text.startIndex
	var renderedToRaw: [Int] = []

	for ref in refs {
		// Add plain text before this ref
		if currentIndex < ref.range.lowerBound {
			let plainText = String(text[currentIndex..<ref.range.lowerBound])
			result.append(NSAttributedString(string: plainText, attributes: baseAttributes))

			// Map each character in plain text
			let rawStartOffset = text.distance(from: text.startIndex, to: currentIndex)
			for i in 0..<plainText.count {
				renderedToRaw.append(rawStartOffset + i)
			}
		}

		// Add styled link (just the target text, not the [[brackets]])
		var linkAttrs = baseAttributes
		linkAttrs[.link] = ref.url
		linkAttrs[.foregroundColor] = tintColor
		result.append(NSAttributedString(string: ref.target, attributes: linkAttrs))

		// Map each character in the rendered link text to raw text positions
		let rawRefStart = text.distance(from: text.startIndex, to: ref.range.lowerBound)
		let targetLength = ref.target.count

		// For the link text, map to positions within the raw ref syntax
		// E.g., for [[World]], "World" chars map to positions 2,3,4,5,6 (skipping [[)
		let bracketOffset = ref.kind.bracketOffset(for: String(text[ref.range]))

		for i in 0..<targetLength {
			// Map to the corresponding character in the raw target
			renderedToRaw.append(rawRefStart + bracketOffset + i)
		}

		currentIndex = ref.range.upperBound
	}

	// Add remaining text after last ref
	if currentIndex < text.endIndex {
		let remaining = String(text[currentIndex...])
		result.append(NSAttributedString(string: remaining, attributes: baseAttributes))

		let rawStartOffset = text.distance(from: text.startIndex, to: currentIndex)
		for i in 0..<remaining.count {
			renderedToRaw.append(rawStartOffset + i)
		}
	}

	// Add final position (for cursor at end)
	renderedToRaw.append(text.count)

	return AttributedStringResult(indexMapping: IndexMapping(renderedToRaw: renderedToRaw), attributedString: result)
}
