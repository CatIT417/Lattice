import SwiftUI
import SQLiteData

struct ChildrenRenderer: View {
	var parentID: Block.ID
	var showIndentLine: Bool = false
	var onIndentLineTapped: (() -> Void)?

	@Environment(\.blockTree) var tree

	var body: some View {
		if !tree.children(of: parentID).isEmpty {
			LazyVStack(alignment: .leading, spacing: 4) {
				ForEach(tree.children(of: parentID)) { child in
					ParagraphView(paragraph: child)
				}
			}
			.padding(.leading, 28)
			.overlay(alignment: .topLeading) {
				if showIndentLine {
					IndentLine(onTap: onIndentLineTapped)
				}
			}
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
