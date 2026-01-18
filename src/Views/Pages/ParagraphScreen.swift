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

				ChildrenRenderer(parentID: paragraph.id)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.safeAreaPadding()
		}
		.environment(\.blockTree, paragraphWithContent.tree)
	}
}

#Preview {
	let paragraph = previewData { try Paragraph.fetchOne($0) }

	ParagraphScreen(paragraphId: paragraph!.id)
		.preview()
}
