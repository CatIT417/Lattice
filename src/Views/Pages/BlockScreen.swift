import SwiftUI
import SQLiteData

struct BlockScreen: View {
	@FetchOne var page: Page?
	@FetchOne var paragraph: Paragraph?
	@Environment(Router.self) var router

	init(blockID: Block.ID) {
		_page = FetchOne(Page.where { $0.id.in(BlockHierarchy.where { $0.blockId.eq(blockID) }.select { $0.pageId.unsafelyUnwrapped }) && Block.where { $0.id.eq(blockID) && $0.isPage && $0.deletedAt.is(nil) }.exists() })
		_paragraph = FetchOne(Paragraph.find(blockID))
	}

	var body: some View {
		Group {
			if let paragraph {
				ParagraphScreen(paragraphId: paragraph.id)
			} else if let page {
				PageScreen(pageId: page.id)
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
