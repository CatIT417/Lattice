import SwiftUI
import SQLiteData

@main
struct LatticeApp: App {
	init() {
		#if DEBUG
		UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
		#endif

		prepareDependencies {
			try! $0.bootstrapDatabase()
		}
	}

	var body: some Scene {
		WindowGroup("Lattice") {
			RootContainer()
				.handlesExternalEvents(preferring: Set(arrayLiteral: "Lattice"), allowing: Set(arrayLiteral: "*"))
		}
		.handlesExternalEvents(matching: Set(arrayLiteral: "Lattice"))
	}
}
