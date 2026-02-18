import SwiftUI
import SQLiteData

struct ParagraphScreen: View {
	let paragraphId: Paragraph.ID

	@Environment(Router.self) var router
	@FetchOne var paragraphWithContent: Paragraph.WithChildren?

	init(paragraphId: Paragraph.ID) {
		self.paragraphId = paragraphId
		_paragraphWithContent = FetchOne(Paragraph.withChildren(id: paragraphId))
	}

	var body: some View {
		Group {
			if let paragraph = paragraphWithContent?.block, let tree = paragraphWithContent?.tree {
				ScrollView {
					VStack(alignment: .leading, spacing: 12) {
						BreadcrumbsView(blockId: paragraph.id)

						ParagraphView(paragraph: paragraph)

						LinkedReferencesSection(forBlockID: paragraph.id)
							.padding(.top, 12)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.safeAreaPadding()
				}
				#if os(iOS)
				.blockSelectionMenu()
				.doneButtonOnToolbar()
				.navigationBarTitleDisplayMode(.inline)
				#endif
				.syncStatusOnToolbar()
				.toolbar(removing: .title)
				.environment(\.blockTree, tree)
				.environment(\.rootBlockID, paragraph.id)
				.navigationTitle(removeReferences(from: paragraph.string))
			} else {
				ProgressView()
					.onAppear { router.pop() }
			}
		}.task {
			_ = await withErrorReporting {
				try await $paragraphWithContent.load(Paragraph.withChildren(id: paragraphId))
			}
		}
	}
}

#Preview {
	let paragraph = previewData { try Paragraph.fetchOne($0) }

	ParagraphScreen(paragraphId: paragraph!.id)
		.preview()
}
