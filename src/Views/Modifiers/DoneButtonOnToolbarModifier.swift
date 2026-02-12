import SwiftUI

struct DoneButtonOnToolbarModifier: ViewModifier {
	@FocusState private var isFocused: Bool

	func body(content: Content) -> some View {
		content
		#if os(iOS)
		.focused($isFocused)
		.toolbar {
			if isFocused {
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						UIApplication.shared.resignFirstResponder()
					}
				}
			}
		}
		#endif
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
