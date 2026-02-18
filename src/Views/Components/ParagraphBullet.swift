import SwiftUI

struct ParagraphBullet: View {
	var paragraph: Paragraph

	@Environment(\.rootBlockID) private var rootBlockID
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		switch paragraph.viewType {
			case .bullet: bullet
			case .document: EmptyView()
			case .numbered: numberBullet
		}
	}

	var numberBullet: some View {
		Text("\(paragraph.order + 1).")
			.foregroundStyle(.secondary)
	}

	var bullet: some View {
		Group {
			if !paragraph.isOpen, paragraph.id != rootBlockID {
				ZStack {
					Circle()
						.fill(colorScheme == .dark ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
						.frame(width: 10, height: 10)

					Circle()
						.fill(Color.primary)
						.frame(width: 5, height: 5)
				}
				.padding(.top, -2.5)
				.padding(.horizontal, -2.5)
			} else {
				Circle()
					.fill(Color.primary)
					.frame(width: 5, height: 5)
			}
		}
	}
}
