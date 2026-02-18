import SwiftUI
import Combine
import SQLiteData

fileprivate func query(for date: Date) -> SelectOf<Page> {
	let day: DayOfYear? = DayOfYear(date)

	return Page
		.where { $0.dailyNoteDate.isNot(nil) && $0.dailyNoteDate <= day }
		.order(by: { $0.dailyNoteDate.desc() })
}

struct DailyPagesScreen: View {
	@State private var currentDate = Date()
	let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

	@Environment(Router.self) private var router
	@FetchAll(query(for: Date())) var pages: [Page]
	@Dependency(\.defaultDatabase) private var database

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
			.scrollTargetLayout()
		}
		.task(id: currentDate.timeIntervalSince1970) {
			let _ = await withErrorReporting {
				try await $pages.load(query(for: currentDate))
			}
		}
		.onReceive(timer) { newDate in
			if Calendar.current.isDate(currentDate, equalTo: newDate, toGranularity: .day) { return }

			currentDate = newDate
		}
		#if os(iOS)
		.blockSelectionMenu()
		.doneButtonOnToolbar()
		#endif
		.syncStatusOnToolbar()
		.navigationTitle("Daily Notes")
		.toolbarTitleDisplayMode(.inline)
		.toolbar {
			#if os(iOS)
			ToolbarItem(placement: .topBarTrailing) {
				GoToDailyPageButton()
			}
			#endif
		}
	}
}

#Preview {
	let _ = previewData()

	DailyPagesScreen()
		.preview()
}
