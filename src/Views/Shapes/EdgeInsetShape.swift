import SwiftUI

struct EdgeInsetShape<Base: Shape>: Shape {
	var base: Base
	var edge: Edge
	var insetAmount: CGFloat = 0

	func path(in rect: CGRect) -> Path {
		var adjustedRect = rect

		switch edge {
			case .top:
				adjustedRect.origin.y += insetAmount
				adjustedRect.size.height -= insetAmount
			case .bottom:
				adjustedRect.size.height -= insetAmount
			case .leading:
				adjustedRect.origin.x += insetAmount
				adjustedRect.size.width -= insetAmount
			case .trailing:
				adjustedRect.size.width -= insetAmount
		}

		return base.path(in: adjustedRect)
	}
}

extension Shape {
	func inset(_ edge: Edge, by amount: CGFloat) -> some Shape {
		EdgeInsetShape(base: self, edge: edge, insetAmount: amount)
	}
}
