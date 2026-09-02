import SwiftUI
import SQLiteData

struct BlockScreen: View {
	@FetchOne var block: Block?
	@Environment(Router.self) var router

	init(blockID: Block.ID) {
		_block = FetchOne(Block.find(blockID))
	}

	var body: some View {
		Group {
			if let block {
				switch block.kind {
					case let .page(page): PageScreen(pageId: page.id)
					case let .paragraph(paragraph): ParagraphScreen(paragraphId: paragraph.id)
				}
			} else {
				ProgressView()
					.onAppear { router.pop() }
			}
		}
	}
}

#Preview {
	let block = previewData { try Block.fetchOne($0) }

	BlockScreen(blockID: block!.id)
		.preview()
}
