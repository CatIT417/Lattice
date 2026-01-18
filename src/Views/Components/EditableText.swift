import SwiftUI

struct EditableText: View {
	let text: String
	let onSave: (String) -> Void
	let onReturn: () -> Void

	@State private var isEditing = false
	@State private var editText = ""
	@FocusState private var isFocused: Bool
	@State private var selection: TextSelection?

	var body: some View {
		Group {
			if isEditing {
				TextField("", text: $editText, selection: $selection, axis: .vertical)
					.focused($isFocused)
					.textFieldStyle(.plain)
					.submitLabel(.return)
					.onSubmit {
						commitEdit()
						onReturn()
					}
					.onChange(of: isFocused) { _, focused in
						if focused { selection = TextSelection(insertionPoint: editText.endIndex) }
						else { commitEdit() }
					}
					.onChange(of: editText) { oldValue, newValue in
						guard isFocused else { return }
						guard !oldValue.contains("\n"), newValue.contains("\n") else { return }

						editText = newValue.replacing("\n", with: "")
						commitEdit()
						onReturn()
					}
			} else {
				Button(action: startEditing) {
					RenderText(text: text)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.foregroundStyle(.primary)
			}
		}
	}

	private func startEditing() {
		editText = text
		isEditing = true
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
			isFocused = true
		}
	}

	private func commitEdit() {
		guard isEditing else { return }
		isEditing = false
		if editText != text {
			onSave(editText)
		}
	}
}

#Preview("Display Mode") {
	EditableText(
		text: "Hello [[World]]!",
		onSave: { _ in },
		onReturn: {}
	)
	.padding()
	.preview()
}

#Preview("Long Text") {
	EditableText(
		text: "This is a longer piece of text that might wrap to multiple lines when displayed in the editor.",
		onSave: { _ in },
		onReturn: {}
	)
	.padding()
	.preview()
}
