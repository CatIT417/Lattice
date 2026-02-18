import SwiftUI

struct RotateTransitionModifier: ViewModifier {
	let angle: Angle
	let anchor: UnitPoint

	func body(content: Content) -> some View {
		content
			.rotationEffect(angle, anchor: anchor)
	}
}

extension AnyTransition {
	static func rotate(angle: Angle, anchor: UnitPoint = .center) -> AnyTransition {
		.modifier(
			active: RotateTransitionModifier(angle: angle, anchor: anchor),
			identity: RotateTransitionModifier(angle: .zero, anchor: anchor)
		)
	}
}
