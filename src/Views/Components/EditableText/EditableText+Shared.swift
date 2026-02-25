import Foundation

// MARK: - Reference Suggestions

extension EditableTextView.Coordinator {
	func shouldActivateReferenceSuggestionSession(for replacementText: String, range: NSRange, currentText: NSString) -> Bool {
		replacementText == "#"
			|| (
				replacementText == "["
					&& range.location > 0
					&& currentText.substring(with: NSRange(location: range.location - 1, length: 1)) == "["
			)
	}
}

// MARK: - Heading Shortcut

extension EditableTextView.Coordinator {
	/// Returns a heading level if the user typed a space after 1–3 `#` characters at the start of the text.
	func shouldSetHeading(for replacementText: String, range: NSRange, currentText: NSString) -> Block.HeadingLevel? {
		guard replacementText == " ", range.length == 0 else { return nil }

		let hashCount = range.location
		guard hashCount >= 1, hashCount <= 3 else { return nil }
		guard currentText.substring(with: NSRange(location: 0, length: hashCount)) == String(repeating: "#", count: hashCount) else { return nil }

		return Block.HeadingLevel(rawValue: hashCount)
	}
}

// MARK: - Bracket Pairs

extension EditableTextView.Coordinator {
	private static let bracketPairs: [Character: Character] = [
		"[": "]",
		"(": ")",
	]

	/// Returns the text to insert (open + close) if the typed character is an opening bracket.
	func shouldAutoComplete(for typedText: String) -> String? {
		guard typedText.count == 1, let typedChar = typedText.first, let closingChar = Self.bracketPairs[typedChar] else { return nil }
		return "\(typedChar)\(closingChar)"
	}

	/// Returns the range to delete if the cursor is between a matching bracket pair.
	func shouldAutoDelete(in currentText: String, at offset: Int) -> NSRange? {
		guard offset > 0, offset < currentText.utf16Length else { return nil }
		guard let charBefore = currentText.character(beforeUTF16Offset: offset) else { return nil }
		guard let charAfter = currentText.character(atUTF16Offset: offset) else { return nil }
		guard Self.bracketPairs[charBefore] == charAfter else { return nil }
		return NSRange(location: offset - 1, length: 2)
	}

	/// Returns true if the typed character is a closing bracket that matches the character at cursor.
	func shouldSkipClosingBracket(for typedText: String, in currentText: String, at offset: Int) -> Bool {
		guard typedText.count == 1, let typedChar = typedText.first, offset < currentText.utf16Length else { return false }
		guard let charAtCursor = currentText.character(atUTF16Offset: offset) else { return false }
		return Self.bracketPairs.values.contains(typedChar) && charAtCursor == typedChar
	}

	/// Returns a markdown link if the replacement text is a URL and text is selected.
	func markdownLinkFromPastedURL(for replacementText: String, selectedText: String) -> String? {
		guard !selectedText.isEmpty, !replacementText.isEmpty, !replacementText.contains("\n"),
		      let url = URL(string: replacementText), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
		else { return nil }

		return "[\(selectedText)](\(replacementText))"
	}

	/// Returns the wrapped text if the typed character is an opening bracket and text is selected.
	func wrapWithBrackets(for typedText: String, selectedText: String) -> String? {
		guard !selectedText.isEmpty, typedText.count == 1, let typedChar = typedText.first, let closingChar = Self.bracketPairs[typedChar] else { return nil }
		return "\(typedChar)\(selectedText)\(closingChar)"
	}
}
