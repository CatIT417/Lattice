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

			Tab("Search", systemImage: "magnifyingglass", value: Tabs.search, role: .search) {
				NavigationContainer(parentRouter: router, tab: .search) {
					SearchScreen()
				}
			}
		}
		#if os(iOS)
		.postNotificationOnStateChange()
		#endif
		.onAppear { createDailyNoteIfNeeded() }
	}

	func createDailyNoteIfNeeded() {
		withErrorReporting {
			guard let hasPage = try database.read({ db in
				try Values(Page.where { $0.dailyNoteDate.eq(#bind(Date())) }.exists()).fetchOne(db)
			}), !hasPage else { return }

			try database.write { db in
				try Page.insert { Page.createDailyNote(for: Date()) }.execute(db)
			}
		}
	}
}

#Preview {
	let _ = withErrorReporting {
		try prepareDependencies {
			try $0.bootstrapDatabase()
		}
	}

	RootContainer()
		.preview(wrapInNavigation: false)
}
