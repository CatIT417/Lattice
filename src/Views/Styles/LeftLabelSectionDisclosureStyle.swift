import SwiftUI

struct LeftLabelSectionDisclosureStyle: DisclosureGroupStyle {
	var hidesArrowOnHover = false

	@State private var isHovering = false

	func makeBody(configuration: Configuration) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .center) {
				Button(action: { configuration.isExpanded.toggle() }) {
					Image(systemName: "triangle.fill")
						.imageScale(.small)
						.font(.caption2)
						.foregroundStyle(.tertiary)
						.animation(.easeIn(duration: 0.1)) {
							$0
								.rotationEffect(.degrees(configuration.isExpanded ? 180 : 90))
							#if os(macOS)
								.opacity(!hidesArrowOnHover || isHovering ? 1 : 0)
							#endif
						}
				}
				.buttonStyle(.plain)
				#if os(macOS)
					.pointerStyle(.link)
				#endif

				configuration.label

				Spacer()
			}
			.hovering($isHovering)

			if configuration.isExpanded {
				configuration.content
			}
		}
	}
}

#Preview {
	DisclosureGroup("Section Title") {
		Text("Section content goes here.")
	}
	.disclosureGroupStyle(LeftLabelSectionDisclosureStyle())
	.padding()
	.preview()
}
