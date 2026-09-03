import Combine
import SwiftUI
import SQLiteData

fileprivate let dailyPageBatchSize = 30
fileprivate let dailyPageLoadThreshold = 5

fileprivate func dailyPagesQuery(for date: Date, limit: Int) -> SelectOf<Page> {
	let day: DayOfYear? = DayOfYear(date)

	return Page
		.where { $0.dailyNoteDate.isNot(nil) && $0.dailyNoteDate <= day }
		.order(by: { $0.dailyNoteDate.desc() })
		.limit(limit)
}

struct DailyPagesScreen: View {
	private struct QueryID: Equatable {
		let day: DayOfYear
		let limit: Int
	}

	@State private var currentDate = Date()
	@State private var pageLimit = dailyPageBatchSize
	let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

	@FetchAll(dailyPagesQuery(for: Date(), limit: dailyPageBatchSize)) private var pages
	var body: some View {
		ScrollView {
			LazyVStack {
				ForEach(pages.enumerated(), id: \.element.id) { i, page in
					VStack(spacing: 8) {
						if i > 0 {
							Divider()
								.padding(.bottom, 20)
						}

						PageView(pageId: page.id)
							.frame(minHeight: 250, alignment: .top)
					}
					.onAppear { loadMorePagesIfNeeded(after: i) }
				}
			}
			.scrollTargetLayout()
		}
		.unfocusBlockOnBackgroundTap()
		.referenceSuggestionsOverlay()
		.task(id: QueryID(day: DayOfYear(currentDate), limit: pageLimit)) {
			let _ = await withErrorReporting {
				try await $pages.load(dailyPagesQuery(for: currentDate, limit: pageLimit)).task
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
		.roamImport()
		.diagnostics()
		.navigationTitle("Daily Notes")
		.toolbarTitleDisplayMode(.inlineLarge)
		.toolbar {
			#if os(iOS)
			ToolbarItem(placement: .primaryAction) {
				GoToDailyPageButton()
			}
			#endif
		}
	}

	private func loadMorePagesIfNeeded(after index: Int) {
		guard index >= pages.count - dailyPageLoadThreshold, pages.count == pageLimit else { return }

		pageLimit += dailyPageBatchSize
	}
}

#Preview {
	let _ = previewData()

	DailyPagesScreen()
		.preview()
}
