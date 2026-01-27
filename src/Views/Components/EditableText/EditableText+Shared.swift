// MARK: - Auto Complete

extension EditableTextView.Coordinator {
	struct AutoComplete {
		struct Action {
			let cursorOffset: Int
			let textToInsert: String
		}

		let trigger: Character
		let preceding: Character
		let insert: String
		let cursorOffset: Int
	}

	var autoCompletePairs: [AutoComplete] { [
		AutoComplete(trigger: "[", preceding: "[", insert: "[]]", cursorOffset: 1),
	] }

	func shouldAutoComplete(for typedText: String, in currentText: String, at offset: Int) -> AutoComplete.Action? {
		guard typedText.count == 1, let typedChar = typedText.first, offset > 0, let index = currentText.index(currentText.startIndex, offsetBy: offset, limitedBy: currentText.endIndex), index > currentText.startIndex
		else { return nil }

		let charBefore = currentText[currentText.index(before: index)]

		for pair in autoCompletePairs where typedChar == pair.trigger && charBefore == pair.preceding {
			return AutoComplete.Action(cursorOffset: pair.cursorOffset, textToInsert: pair.insert)
		}

		return nil
	}
}
