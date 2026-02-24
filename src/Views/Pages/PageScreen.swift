import SwiftUI
import SQLiteData

struct PageScreen: View {
	let pageId: Page.ID

	@Environment(Router.self) var router
	@FetchOne var pageWithContent: Page.WithChildren?

	var hasNoChildren: Bool {
		pageWithContent?.tree.children(of: pageId).isEmpty ?? true
	}

	init(pageId: Page.ID) {
		self.pageId = pageId
		_pageWithContent = FetchOne(Page.withChildren(id: pageId), animation: .default)
	}

	var body: some View {
		Group {
			if let page = pageWithContent?.block, let pageWithContent {
				ScrollView {
					VStack(alignment: .leading, spacing: 12) {
						if hasNoChildren {
							PlaceholderBlock(pageId: page.id)
								.padding(.leading, 6)
						}

						ChildrenRenderer(parentID: page.id, skipPadding: true)

						LinkedReferencesSection(forBlockID: page.id)
							.padding(.top, 12)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.safeAreaPadding()
				}
				#if os(iOS)
				.blockSelectionMenu()
				.doneButtonOnToolbar()
				.toolbar {
					if let dailyNoteDate = page.dailyNoteDate {
						ToolbarItem {
							GoToDailyPageButton(currentDate: dailyNoteDate.date())
						}
					}
				}
				#endif
				.referenceSuggestionsOverlay()
				.syncStatusOnToolbar()
				.navigationTitle(page.title)
				.navigationDocument(page, preview: SharePreview(page.title))
				.toolbarTitleDisplayMode(.inline)
				.toolbarRole(.editor)
				.environment(\.rootBlockID, page.id)
				.environment(\.blockTree, pageWithContent.tree)
			} else {
				ProgressView()
					.onAppear { router.pop() }
			}
		}
		.task {
			_ = await withErrorReporting {
				try await $pageWithContent.load(Page.withChildren(id: pageId), animation: .default)
			}
		}
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
