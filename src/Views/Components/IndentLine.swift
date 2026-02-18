import SwiftUI
import Dependencies

struct IndentLine: View {
	var onTap: (() -> Void)?

	@State private var isHovering = false
	@Dependency(\.platform) var platform
	@Environment(\.colorScheme) var colorScheme

	var separatorColor: HierarchicalShapeStyle {
		#if os(macOS)
		if isHovering { HierarchicalShapeStyle.quaternary }
		else { HierarchicalShapeStyle.quinary }
		#else
		if isHovering, colorScheme != .light { HierarchicalShapeStyle.tertiary }
		else { HierarchicalShapeStyle.quaternary }
		#endif
	}

	var body: some View {
		Capsule()
			.fill(separatorColor)
			.frame(width: isHovering ? 4 : 1, alignment: .center)
			.offset(x: isHovering ? -1.5 : 0)
			.padding(.horizontal, platform.hasPointer ? 6 : 8)
			.hovering($isHovering.animation(.easeInOut(duration: 0.2)))
			.padding(.leading, 2.5)
			.contentShape(Rectangle())
		#if os(iOS)
			.hoverEffect(.lift)
		#endif
			.onTapGesture { onTap?() }
			.padding(.horizontal, platform.hasPointer ? -6 : -8)
		#if os(macOS)
			.pointerStyle(.link)
		#endif
	}
}
