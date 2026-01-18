import SwiftUI
import SQLiteData

@main
struct LatticeApp: App {
	init() {
		withErrorReporting {
			try prepareDependencies {
				try $0.bootstrapDatabase()
			}
		}
	}

	var body: some Scene {
		WindowGroup {
			NavigationContainer(parentRouter: Router(level: 0)) {
				ContentView()
			}
		}
	}
}
