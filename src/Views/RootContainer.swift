import SwiftUI
import SQLiteData

fileprivate typealias Tabs = Destination.Tabs

struct RootContainer: View {
	@Dependency(\.defaultDatabase) var database
	@Dependency(\.defaultSyncEngine) var syncEngine
	@State var router = Router(level: 0, identifierTab: nil)

	var body: some View {
		TabView(selection: $router.selectedTab) {
			Tab("Daily Notes", systemImage: "calendar", value: Tabs.daily) {
				NavigationContainer(parentRouter: router, tab: .daily) {
					DailyPagesScreen()
						.toolbar {
							ToolbarItem {
								Image(systemName: syncEngine.isSynchronizing ? "arrow.trianglehead.2.clockwise.rotate.90.icloud" : "checkmark.icloud")
									.imageScale(.small)
							}
							.sharedBackgroundVisibility(.hidden)
						}
				}
			}

			Tab(value: Tabs.search, role: .search) {
				NavigationContainer(parentRouter: router, tab: .search) {
					SearchScreen()
						.toolbar {
							ToolbarItem {
								Image(systemName: syncEngine.isSynchronizing ? "arrow.trianglehead.2.clockwise.rotate.90.icloud" : "checkmark.icloud")
									.imageScale(.small)
							}
							.sharedBackgroundVisibility(.hidden)
						}
				}
			}
		}
		.onAppear { createDailyNoteIfNeeded() }
		.tabViewSearchActivation(.searchTabSelection)
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
