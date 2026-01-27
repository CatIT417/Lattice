import SwiftUI
import SQLiteData

struct PageView: View {
	@FetchOne var pageWithContent: Page.WithChildren? = nil
	@State private var blockCoordinator = BlockCoordinator()

	init(pageId: Page.ID) {
		_pageWithContent = FetchOne(Page.withChildren(id: pageId))
	}

	var body: some View {
		if let page = pageWithContent?.block, let tree = pageWithContent?.tree {
			VStack {
				NavigationButton(push: .page(id: page.id)) {
					Text(page.title)
						.font(.title.weight(.semibold))
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.foregroundStyle(.primary)
				.buttonStyle(.plain)
				#if os(macOS)
					.pointerStyle(.link)
				#endif

				VStack(alignment: .leading, spacing: 12) {
					if tree.children(of: page.id).isEmpty {
						PlaceholderBlock(pageId: page.id)
							.padding(.leading, 24)
					}

					ChildrenRenderer(parentID: page.id)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.safeAreaPadding()
			.environment(\.blockTree, tree)
			.environment(\.blockCoordinator, blockCoordinator)
		}
	}
}

#Preview {
	let page = previewData { try Page.fetchOne($0) }

	PageView(pageId: page!.id)
		.preview()
}
