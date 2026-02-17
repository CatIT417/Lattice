#if os(iOS)
import SwiftUI
import Dependencies

struct DoneButtonOnToolbarModifier: ViewModifier {
	@FocusState private var isFocused: Bool
	@Dependency(\.blockSelectionCoordinator) private var selectionCoordinator

	func body(content: Content) -> some View {
		content
			.focused($isFocused)
			.transaction({ $0.animation = nil }) {
				$0.toolbar {
					if isFocused || selectionCoordinator.hasSelection {
						ToolbarItem(placement: .confirmationAction) {
							Button(role: .confirm, action: markAsDone)
						}
					}
				}
			}
	}

	func markAsDone() {
		UIImpactFeedbackGenerator(style: .medium).impactOccurred()

		if selectionCoordinator.hasSelection { selectionCoordinator.clearSelection() }
		else { UIApplication.shared.dismissKeyboard() }
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
#endif
