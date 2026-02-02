import SwiftUI
import SQLiteData

fileprivate typealias Tabs = Destination.Tabs

struct RootContainer: View {
	@Dependency(\.defaultDatabase) var database
	@State var router = Router(level: 0, identifierTab: nil)

	var body: some View {
		TabView(selection: $router.selectedTab) {
			Tab("Daily Notes", systemImage: "calendar", value: Tabs.daily) {
				NavigationContainer(parentRouter: router, tab: .daily) {
					DailyPagesScreen()
				}
			}

			Tab(value: Tabs.search, role: .search) {
				NavigationContainer(parentRouter: router, tab: .search) {
					SearchScreen()
				}
			}
		}
		.tabViewSearchActivation(.searchTabSelection)
		#if os(iOS)
			.postNotificationOnStateChange()
		#endif
			.onAppear { createDailyNoteIfNeeded() }
	}

	func createDailyNoteIfNeeded() {
		@Dependency(\.date.now) var now

		withErrorReporting {
			guard let hasPage = try database.read({ db in
				try Values(Page.where { $0.dailyNoteDate.eq(#bind(now)) }.exists()).fetchOne(db)
			}), !hasPage else { return }

			try database.write { db in
				try Page.insert { Page.createDailyNote(for: now) }.execute(db)
			}
		}
	}
}

#Preview {
	let _ = previewData()

	RootContainer()
		.preview(wrapInNavigation: false)
}
