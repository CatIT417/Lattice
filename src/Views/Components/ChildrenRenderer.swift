import SwiftUI
import SQLiteData

struct ChildrenRenderer: View {
	var parentID: Block.ID

	@Environment(\.blockTree) var tree

	var body: some View {
		if let tree, !tree.children(of: parentID).isEmpty {
			VStack(alignment: .leading, spacing: 4) {
				ForEach(tree.children(of: parentID)) { child in
					ParagraphView(paragraph: child)
				}
			}
			.padding(.leading, 24)
		}
	}
}

struct ChildrenRenderer_Previews: PreviewProvider {
	static var previews: some View {
		let (page, paragraphs) = previewData { db in
			let page = try Page.fetchOne(db)!
			let paragraphs = try Paragraph.where { $0.pageId == page.id }.fetchAll(db)

			return (page, paragraphs)
		}

		ScrollView {
			ChildrenRenderer(parentID: page.id)
				.environment(\.blockTree, BlockTree(paragraphs: paragraphs))
		}
		.preview()
	}
}
