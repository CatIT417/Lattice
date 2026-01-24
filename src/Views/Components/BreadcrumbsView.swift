import SwiftUI
import SQLiteData

struct BreadcrumbsView: View {
	@FetchAll var breadcrumbs: [Breadcrumb]

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
							.foregroundStyle(.secondary)
					}
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
		let ancestor = previewData { try Ancestor.order { $0.depth.desc() }.fetchOne($0)! }

		BreadcrumbsView(blockId: ancestor.blockId)
			.preview()
	}
}
