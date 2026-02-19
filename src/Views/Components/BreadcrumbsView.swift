import SwiftUI
import SQLiteData

struct BreadcrumbsView: View {
	@FetchAll(Breadcrumb.none) var breadcrumbs: [Breadcrumb]

	@Environment(\.isNavigationEnabled) private var isNavigationEnabled

	init(blockId: Block.ID) {
		_breadcrumbs = FetchAll(Breadcrumb.forBlock(id: blockId))
	}

	var body: some View {
		if !breadcrumbs.isEmpty {
			HStack(spacing: 4) {
				ForEach(breadcrumbs, id: \.id) { ancestor in
					NavigationButton(push: ancestor.page) {
						Text(ancestor.text)
							.lineLimit(1)
							.foregroundStyle(isNavigationEnabled ? .secondary : .primary)
					}
					.foregroundStyle(.primary)
					.buttonStyle(.plain)
					#if os(macOS)
						.pointerStyle(.link)
					#endif

					if ancestor.id != breadcrumbs.last?.id {
						Image(systemName: "chevron.right")
							.font(.caption2)
							.foregroundStyle(.tertiary)
					}
				}
			}
			.font(.subheadline)
		}
	}
}

struct BreadcrumbsView_Previews: PreviewProvider {
	static var previews: some View {
		let ancestor = previewData { try Ancestor.order { $0.depth.desc() }.fetchOne($0) }

		BreadcrumbsView(blockId: ancestor!.blockId)
			.preview()
	}
}
