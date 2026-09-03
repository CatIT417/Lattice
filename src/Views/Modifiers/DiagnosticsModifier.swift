import SwiftUI

struct DiagnosticsModifier: ViewModifier {
	@State private var isPresented = false

	func body(content: Content) -> some View {
		content
			.toolbar {
				ToolbarItem(placement: .secondaryAction) {
					Button("Diagnostics", systemImage: "stethoscope") {
						isPresented = true
					}
				}
			}
			.sheet(isPresented: $isPresented) {
				DiagnosticsScreen()
			}
	}
}

extension View {
	func diagnostics() -> some View {
		modifier(DiagnosticsModifier())
	}
}
