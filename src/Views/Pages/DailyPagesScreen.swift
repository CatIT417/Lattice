import SwiftUI
import SQLiteData

struct DailyPagesScreen: View {
	@FetchAll(Page.where { $0.dailyNoteDate.isNot(nil) }.order(by: { $0.dailyNoteDate.desc() }))
	var pages: [Page]

	var body: some View {
		ScrollView {
			LazyVStack {
				ForEach(pages.enumerated(), id: \.element.id) { i, page in
					if i > 0 {
						Divider()
							.padding(.bottom, 20)
					}

					PageView(pageId: page.id)
						.frame(minHeight: 150, alignment: .top)
				}
			}
		}
		.navigationTitle("Daily Notes")
		.toolbarTitleDisplayMode(.inline)
		.syncStatusOnToolbar()
		.doneButtonOnToolbar()
	}
}

#Preview {
	let _ = previewData()

	DailyPagesScreen()
		.preview()
}
