import SwiftUI
import SQLiteData

struct PageScreen: View {
	let pageId: Page.ID

	@Environment(Router.self) var router
	@Dependency(\.defaultDatabase) var database
	@FetchOne var pageWithContent: Page.WithChildren?

	@State private var willDeletePage = false
	@State private var willRenamePage = false

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

						UnlinkedReferencesSection(forPage: page.id, title: page.title)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.safeAreaPadding()
				}
				#if os(iOS)
				.doneButtonOnToolbar()
				.toolbar {
					if let dailyNoteDate = page.dailyNoteDate {
						ToolbarItem {
							GoToDailyPageButton(currentDate: dailyNoteDate.date())
						}
					}
				}
				.toolbarTitleMenu {
					if !page.isDailyNote, !page.isSpecialPage {
						Button("Rename", systemImage: "pencil") {
							willRenamePage = true
						}

						Button("Delete", systemImage: "trash", role: .destructive) {
							willDeletePage = true
						}
					}
				}
				.blockSelectionMenu()
				#else
				.toolbar {
					ShareLink(item: page, preview: SharePreview(page.title))

					if !page.isDailyNote, !page.isSpecialPage {
						Menu {
							Button("Rename", systemImage: "pencil") {
								willRenamePage = true
							}

							Button("Delete", systemImage: "trash", role: .destructive) {
								willDeletePage = true
							}
						} label: {
							Image(systemName: "ellipsis.circle")
						}
					}
				}
				#endif
				.alert("Are you sure you want to delete this page?", isPresented: $willDeletePage) {
					Button("Delete", role: .destructive) {
						deletePage()
					}

					Button(role: .cancel) {}
				} message: {
					Text("Any blocks referencing this page will have their content altered as well.")
				}
				.toolbarRole(.editor)
				.syncStatusOnToolbar()
				.navigationTitle(page.title)
				.referenceSuggestionsOverlay()
				.toolbarTitleDisplayMode(.inline)
				.environment(\.rootBlockID, page.id)
				.focusedSceneValue(\.currentPage, page)
				.renamePage(page, active: $willRenamePage)
				.environment(\.blockTree, pageWithContent.tree)
				.navigationDocument(page, preview: SharePreview(page.title))
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

	func deletePage() {
		withErrorReporting {
			try database.write { db in
				try Page.find(pageId).delete().execute(db)
			}

			router.navigationStackPath.removeAll(where: { $0 == .page(id: pageId) })
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
