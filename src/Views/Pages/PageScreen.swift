import SwiftUI
import SQLiteData

struct PageScreen: View {
	@FetchOne var pageWithContent: Page.WithChildren!

	var page: Page {
		pageWithContent.block
	}

	init(pageId: Page.ID) {
		_pageWithContent = FetchOne(Page.withChildren(id: pageId))
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				ChildrenRenderer(parentID: page.id)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.safeAreaPadding()
		}
		.navigationTitle(page.title)
		.environment(\.blockTree, pageWithContent.tree)
	}
}

#Preview {
	let page = previewData { try Page.fetchOne($0) }

	PageScreen(pageId: page!.id)
		.preview()
}
