import SwiftUI
import SQLiteData

struct BlockScreen: View {
	@FetchOne var block: Block!

	init(blockID: Block.ID) {
		_block = FetchOne(Block.find(blockID))
	}

	var body: some View {
		Group {
			switch block.kind {
				case let .page(page): PageScreen(pageId: page.id)
				case let .paragraph(paragraph): ParagraphScreen(paragraphId: paragraph.id)
			}
		}
	}
}

#Preview {
	let block = previewData { try Block.fetchOne($0) }

	BlockScreen(blockID: block!.id)
		.preview()
}
