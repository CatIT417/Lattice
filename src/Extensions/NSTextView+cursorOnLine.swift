#if os(macOS)
import AppKit

extension NSTextView {
	func isCursorOnFirstLine() -> Bool {
		guard let layoutManager else { return true }

		let textLength = string.count
		guard textLength > 0 else { return true }

		let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(selectedRange().location, textLength - 1))

		var lineRange = NSRange()
		layoutManager.lineFragmentRect(forGlyphAt: max(0, glyphIndex), effectiveRange: &lineRange)

		// Cursor is on first line if the line starts at glyph 0
		return lineRange.location == 0
	}

	func isCursorOnLastLine() -> Bool {
		guard let layoutManager else { return true }

		let textLength = string.count
		guard textLength > 0 else { return true }

		let cursorGlyphIndex = layoutManager.glyphIndexForCharacter(at: min(selectedRange().location, textLength - 1))
		let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: textLength - 1)

		var lastLineRange = NSRange()
		var cursorLineRange = NSRange()
		layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: &lastLineRange)
		layoutManager.lineFragmentRect(forGlyphAt: cursorGlyphIndex, effectiveRange: &cursorLineRange)

		// Cursor is on last line if both are in the same line fragment
		return cursorLineRange.location == lastLineRange.location
	}
}
#endif
