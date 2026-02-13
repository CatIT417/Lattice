import SwiftUI
import SQLiteData

struct PageScreen: View {
	@FetchOne var pageWithContent: Page.WithChildren!

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

				LinkedReferencesSection(forBlockID: page.id)
					.padding(.top, 12)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.safeAreaPadding()
		}
		.task {
			_ = await withErrorReporting {
				try await $pageWithContent.load(Page.withChildren(id: page.id))
			}
		}
		.syncStatusOnToolbar()
		.doneButtonOnToolbar()
		.navigationTitle(page.title)
		.environment(\.rootBlockID, page.id)
		.environment(\.blockTree, pageWithContent.tree)
	}
}

extension PageScreen {
	struct ByTitle: View {
		var title: String

		@State var page: Page?
		@Dependency(\.defaultDatabase) var database

		init(title: String) {
			self.title = title
		}

		var body: some View {
			if let page {
				PageScreen(pageId: page.id)
			} else {
				ProgressView()
					.onAppear { findOrCreate() }
			}
		}

		func findOrCreate() {
			page = withErrorReporting {
				try database.write { db in
					try Page.findOrCreate(title: title, in: db)
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
