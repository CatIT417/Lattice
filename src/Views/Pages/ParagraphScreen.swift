import SwiftUI
import SQLiteData

struct ParagraphScreen: View {
	@FetchOne var paragraphWithContent: Paragraph.WithChildren!

	var paragraph: Paragraph {
		paragraphWithContent.block
	}

	init(paragraphId: Paragraph.ID) {
		_paragraphWithContent = FetchOne(Paragraph.withChildren(id: paragraphId))
	}

	var body: some View {
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
		.task {
			_ = await withErrorReporting {
				try await $paragraphWithContent.load(Paragraph.withChildren(id: paragraph.id))
			}
		}
		.syncStatusOnToolbar()
		.doneButtonOnToolbar()
		.toolbar(removing: .title)
		.environment(\.rootBlockID, paragraph.id)
		.environment(\.blockTree, paragraphWithContent.tree)
		.navigationTitle(removeReferences(from: paragraph.string))
		#if os(iOS)
			.navigationBarTitleDisplayMode(.inline)
		#endif
	}
}

#Preview {
	let paragraph = previewData { try Paragraph.fetchOne($0) }

	ParagraphScreen(paragraphId: paragraph!.id)
		.preview()
}
