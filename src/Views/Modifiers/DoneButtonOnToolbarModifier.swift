import SwiftUI

struct DoneButtonOnToolbarModifier: ViewModifier {
	@FocusState private var isFocused: Bool

	func body(content: Content) -> some View {
		content
			.focused($isFocused)
			.toolbar {
				if isFocused {
					ToolbarItem {
						Button(role: .confirm) {
							UIApplication.shared.resignFirstResponder()
						}
					}
				}
			}
	}
}

extension View {
	func doneButtonOnToolbar() -> some View {
		modifier(DoneButtonOnToolbarModifier())
	}
}

#Preview {
	TextField("Placeholder", text: .constant(""))
		.doneButtonOnToolbar()
		.preview()
}
