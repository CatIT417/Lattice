import Combine
import Sharing
import SwiftUI
import SQLiteData

fileprivate typealias Tabs = Destination.Tabs

struct RootContainer: View {
	@Environment(\.scenePhase) private var scenePhase
	@Dependency(\.defaultDatabase) var database
	@Dependency(\.defaultSyncEngine) var syncEngine
	@State private var currentDay = DayOfYear.today
	@State private var router = Router(level: 0, identifierTab: nil)
	@State private var duplicatePagesWatcher = DuplicatePagesWatcher()
	@Shared(.appStorage("sidebarCustomizations")) var tabViewCustomization = TabViewCustomization()

	#if os(iOS)
	var iosLayout: some View {
		TabView(selection: $router.selectedTab) {
			Tab("Daily Notes", systemImage: "calendar", value: Tabs.daily) {
				NavigationContainer(parentRouter: router, tab: .daily) {
					DailyPagesScreen(currentDay: currentDay)
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
					DailyPagesScreen(currentDay: currentDay)
				}

				Tab(value: Tabs.search, role: .search) {
					SearchScreen()
				}
			}
		}
		.tabViewStyle(.sidebarAdaptable)
		.clearInitialResponderOnLaunch()
		.tabViewSearchActivation(.searchTabSelection)
		.tabViewCustomization(Binding($tabViewCustomization))
	}
	#endif

	var body: some View {
		Group {
			#if os(iOS)
			iosLayout
			#elseif os(macOS)
			macLayout
			#endif
		}
		.onAppear { duplicatePagesWatcher.start() }
		.task(id: scenePhase) {
			guard scenePhase == .active else { return }
			await refreshToday()
		}
		.onReceive(
			NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
				.merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange), NotificationCenter.default.publisher(for: .NSSystemClockDidChange))
				.receive(on: DispatchQueue.main)
		) { _ in
			guard scenePhase == .active else { return }
			Task { await refreshToday() }
		}
	}

	private func refreshToday() async {
		let day = DayOfYear.today
		currentDay = day

		_ = await withErrorReporting {
			try await database.write { try Page.createDailyNote(for: day, in: $0) }
		}
	}
}

#Preview {
	let _ = previewData()

	RootContainer()
		.preview(wrapInNavigation: false)
}
