import SwiftUI
import SQLiteData

struct ParagraphScreen: View {
	@State private var blockCoordinator = BlockCoordinator()
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
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.safeAreaPadding()
		}
		.toolbar(removing: .title)
		.navigationTitle(removeReferences(from: paragraph.string))
		.navigationBarTitleDisplayMode(.inline)
		.environment(\.blockCoordinator, blockCoordinator)
		.environment(\.blockTree, paragraphWithContent.tree)
	}
}

#Preview {
	let paragraph = previewData { try Paragraph.fetchOne($0) }

	ParagraphScreen(paragraphId: paragraph!.id)
		.preview()
}
