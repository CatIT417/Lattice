import SwiftUI
import Dependencies

struct ReferenceSuggestionsOverlayModifier: ViewModifier {
	@Dependency(\.referenceSuggestionsCoordinator) private var referenceSuggestions

	func body(content: Content) -> some View {
		content
			.coordinateSpace(name: ReferenceSuggestions.coordinateSpace)
			.overlay(alignment: .topLeading) {
				if referenceSuggestions.context != nil {
					FloatingPageSuggestions(referenceSuggestions: referenceSuggestions)
						.zIndex(10000)
				}
			}
			.onDisappear { referenceSuggestions.dismiss() }
	}
}

extension View {
	func referenceSuggestionsOverlay() -> some View {
		modifier(ReferenceSuggestionsOverlayModifier())
	}
}
