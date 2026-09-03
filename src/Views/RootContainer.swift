import Sharing
import SwiftUI
import SQLiteData

fileprivate typealias Tabs = Destination.Tabs

struct RootContainer: View {
	@Dependency(\.defaultDatabase) var database
	@Dependency(\.defaultSyncEngine) var syncEngine
	@State private var router = Router(level: 0, identifierTab: nil)
	@State private var duplicatePagesWatcher = DuplicatePagesWatcher()
	@Shared(.appStorage("sidebarCustomizations")) var tabViewCustomization = TabViewCustomization()

	#if os(iOS)
	var iosLayout: some View {
		TabView(selection: $router.selectedTab) {
			Tab("Daily Notes", systemImage: "calendar", value: Tabs.daily) {
				NavigationContainer(parentRouter: router, tab: .daily) {
					DailyPagesScreen()
				}
			}
			.customizationBehavior(.disabled, for: .sidebar, .tabBar)

			Tab(value: Tabs.search, role: .search) {
				NavigationContainer(parentRouter: router, tab: .search) {
					SearchScreen()
				}
			}
		}
		.postNotificationOnStateChange()
		.onAppear {
			createDailyNoteIfNeeded()
			duplicatePagesWatcher.start()
		}
		.tabViewSearchActivation(.searchTabSelection)
		.tabViewCustomization(Binding($tabViewCustomization))
	}
	#endif

	#if os(macOS)
	var macLayout: some View {
		// putting the navigation container at the top level makes the sidebar disappear on navigation
		// unfortunately, putting it where it should go breaks navigation completely, so this is better 🥲
		NavigationContainer(parentRouter: router, tab: .daily) {
			TabView(selection: $router.selectedTab) {
				Tab("Daily Notes", systemImage: "calendar", value: Tabs.daily) {
					DailyPagesScreen()
				}

				Tab(value: Tabs.search, role: .search) {
					SearchScreen()
				}
			}
		}
		.tabViewStyle(.sidebarAdaptable)
		.clearInitialResponderOnLaunch()
		.onAppear {
			createDailyNoteIfNeeded()
			duplicatePagesWatcher.start()
		}
		.tabViewSearchActivation(.searchTabSelection)
		.tabViewCustomization(Binding($tabViewCustomization))
	}
	#endif

	var body: some View {
		#if os(iOS)
		iosLayout
		#elseif os(macOS)
		macLayout
		#endif
	}

	func createDailyNoteIfNeeded() {
		let date = DayOfYear.today

		withErrorReporting {
			guard let hasPage = try database.read({ db in
				try Select(Page.where { $0.dailyNoteDate.eq(date) }.exists()).fetchOne(db)
			}), !hasPage else { return }

			_ = try database.write { try Page.createDailyNote(for: date, in: $0) }
		}
	}
}

#Preview {
	let _ = previewData()

	RootContainer()
		.preview(wrapInNavigation: false)
}
