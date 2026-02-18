#if os(iOS)
import SwiftUI

struct SwipeActionModifier: ViewModifier {
	var action: () -> Void

	@State private var dragOffset: CGFloat = 0
	@State private var dragStartTranslation: CGFloat?

	func body(content: Content) -> some View {
		content
			.offset(x: dragOffset)
			.simultaneousGesture(swipeGesture)
	}

	private var swipeGesture: some Gesture {
		DragGesture(minimumDistance: 50)
			.onChanged { value in
				let horizontal = value.translation.width
				guard horizontal < 0, abs(horizontal) > abs(value.translation.height) else {
					dragOffset = 0
					return
				}
				if dragStartTranslation == nil {
					dragStartTranslation = horizontal
				}
				let adjusted = horizontal - (dragStartTranslation ?? 0)
				dragOffset = rubberBand(adjusted, limit: 40)
			}
			.onEnded { value in
				dragStartTranslation = nil
				withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
					dragOffset = 0
				}

				guard value.translation.width < 0,
				      abs(value.translation.width) > abs(value.translation.height) else { return }

				action()
				UIImpactFeedbackGenerator(style: .light).impactOccurred()
			}
	}
}

extension View {
	func onSwipeLeft(perform action: @escaping () -> Void) -> some View {
		modifier(SwipeActionModifier(action: action))
	}
}
#endif
