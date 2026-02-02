import SwiftUI
import SQLiteData

struct PageScreen: View {
	@FetchOne var pageWithContent: Page.WithChildren!
	@State private var blockCoordinator = BlockCoordinator()

	var hasNoChildren: Bool {
		pageWithContent.tree.children(of: page.id).isEmpty
	}

	var page: Page {
		pageWithContent.block
	}

	init(pageId: Page.ID) {
		_pageWithContent = FetchOne(Page.withChildren(id: pageId))
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				if hasNoChildren {
					PlaceholderBlock(pageId: page.id)
						.padding(.leading, 24)
				}

				ChildrenRenderer(parentID: page.id)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.safeAreaPadding()
		}
		.doneButtonOnToolbar()
		.navigationTitle(page.title)
		.environment(\.blockTree, pageWithContent.tree)
		.environment(\.blockCoordinator, blockCoordinator)
	}
}

extension PageScreen {
	struct ByTitle: View {
		var title: String

		@FetchOne var page: Page?
		@Dependency(\.defaultDatabase) var database

		init(title: String) {
			self.title = title
			_page = FetchOne(Page.where { $0.title.eq(title) })
		}

		var body: some View {
			if let page {
				PageScreen(pageId: page.id)
			} else {
				ProgressView()
					.onAppear { createPage() }
			}
		}

		func createPage() {
			guard page == nil else { return }

			withErrorReporting {
				try database.write { db in
					try Page.insert { Page(title: title) }.execute(db)
				}
			}
		}
	}
}

#Preview("PageScreen") {
	let page = previewData { try Page.fetchOne($0) }

	PageScreen(pageId: page!.id)
		.preview()
}

#Preview("PageScreen.ByTitle existing") {
	let page = previewData { try Page.fetchOne($0) }

	PageScreen.ByTitle(title: page!.title)
		.preview()
}

#Preview("PageScreen.ByTitle new") {
	let _ = previewData()
	@Dependency(\.uuid) var uuid

	PageScreen.ByTitle(title: "New Page \(uuid().uuidString)")
		.preview()
}
