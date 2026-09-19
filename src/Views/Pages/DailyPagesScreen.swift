import SwiftUI
import SQLiteData

fileprivate let dailyPageBatchSize = 30
fileprivate let dailyPageLoadThreshold = 5

fileprivate func dailyPagesQuery(for day: DayOfYear, limit: Int) -> SelectOf<Page> {
	Page
		.where { $0.dailyNoteDate.isNot(nil) && $0.dailyNoteDate <= Optional(day) }
		.order(by: { $0.dailyNoteDate.desc() })
		.limit(limit)
}

struct DailyPagesScreen: View {
	private struct QueryID: Equatable {
		let day: DayOfYear
		let limit: Int
	}

	let currentDay: DayOfYear

	@State private var pageLimit = dailyPageBatchSize

	@Environment(Router.self) private var router
	@Dependency(\.defaultDatabase) private var database

	@FetchAll(Page.none) private var pages
	var body: some View {
		ScrollViewWithCalendarPicker(currentDay: currentDay, onSelectDate: navigateToDailyPage) {
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
		.referenceSuggestionsOverlay()
		.task(id: QueryID(day: currentDay, limit: pageLimit)) {
			let _ = await withErrorReporting {
				try await $pages.load(dailyPagesQuery(for: currentDay, limit: pageLimit)).task
			}
		}
		#if os(iOS)
		.blockSelectionMenu()
		.doneButtonOnToolbar()
		#endif
		.roamImport()
		.diagnostics()
		.navigationTitle("Daily Notes")
		.toolbarTitleDisplayMode(.inlineLarge)
	}

	private func navigateToDailyPage(for day: DayOfYear, dismissCalendar: () -> Void) {
		withErrorReporting {
			let page = try database.write { db in
				try Page.createDailyNote(for: day, in: db)
			}

			dismissCalendar()
			router.push(.page(id: page.id))
		}
	}

	private func loadMorePagesIfNeeded(after index: Int) {
		guard index >= pages.count - dailyPageLoadThreshold, pages.count == pageLimit else { return }

		pageLimit += dailyPageBatchSize
	}
}

#Preview {
	let _ = previewData()

	DailyPagesScreen(currentDay: .today)
		.preview()
}
