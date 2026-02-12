import SwiftUI
import Sharing
import SQLiteData

fileprivate typealias Tabs = Destination.Tabs

struct RootContainer: View {
	@Dependency(\.defaultDatabase) var database
	@Dependency(\.defaultSyncEngine) var syncEngine
	@State var router = Router(level: 0, identifierTab: nil)
	@Shared(.appStorage("sidebarCustomizations")) var tabViewCustomization = TabViewCustomization()

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
		#if os(iOS)
		// .sidebarAdaptable breaks `Environment` in macOS
		.tabViewStyle(.sidebarAdaptable)
		#endif
		.onAppear { createDailyNoteIfNeeded() }
		.tabViewSearchActivation(.searchTabSelection)
		.tabViewCustomization(Binding($tabViewCustomization))
		#if os(iOS)
			.postNotificationOnStateChange()
		#elseif os(macOS)
			.clearInitialResponderOnLaunch()
		#endif
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
