import Foundation

// MARK: - Bracket Pairs

extension EditableTextView.Coordinator {
	struct BracketPair {
		let open: Character
		let close: Character
	}

	var bracketPairs: [BracketPair] { [
		BracketPair(open: "[", close: "]"),
		BracketPair(open: "(", close: ")"),
	] }

	/// Returns the text to insert (open + close) if the typed character is an opening bracket.
	func shouldAutoComplete(for typedText: String) -> String? {
		guard typedText.count == 1, let typedChar = typedText.first else { return nil }

		for pair in bracketPairs where typedChar == pair.open {
			return "\(pair.open)\(pair.close)"
		}

		return nil
	}

	/// Returns the range to delete if the cursor is between a matching bracket pair.
	func shouldAutoDelete(in currentText: String, at offset: Int) -> NSRange? {
		guard offset > 0, offset < currentText.count else { return nil }

		let index = currentText.index(currentText.startIndex, offsetBy: offset)
		let charBefore = currentText[currentText.index(before: index)]
		let charAfter = currentText[index]

		for pair in bracketPairs where charBefore == pair.open && charAfter == pair.close {
			return NSRange(location: offset - 1, length: 2)
		}

		return nil
	}

	/// Returns true if the typed character is a closing bracket that matches the character at cursor.
	func shouldSkipClosingBracket(for typedText: String, in currentText: String, at offset: Int) -> Bool {
		guard typedText.count == 1, let typedChar = typedText.first, offset < currentText.count else { return false }

		let index = currentText.index(currentText.startIndex, offsetBy: offset)
		let charAtCursor = currentText[index]

		return bracketPairs.contains { $0.close == typedChar && charAtCursor == typedChar }
	}

	/// Returns the wrapped text if the typed character is an opening bracket and text is selected.
	func wrapWithBrackets(for typedText: String, selectedText: String) -> String? {
		guard !selectedText.isEmpty, typedText.count == 1, let typedChar = typedText.first else { return nil }

		for pair in bracketPairs where typedChar == pair.open {
			return "\(pair.open)\(selectedText)\(pair.close)"
		}

		return nil
	}
}
