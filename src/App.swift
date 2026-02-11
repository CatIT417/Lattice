import SwiftUI
import SQLiteData

@main
struct LatticeApp: App {
	var initializationError: (any Error)?

	init() {
		#if DEBUG
		UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
		#endif

		do {
			try prepareDependencies {
				try $0.bootstrapDatabase()
			}
		} catch {
			reportIssue(error)
			initializationError = error
		}
	}

	var body: some Scene {
		WindowGroup("Lattice") {
			if let initializationError {
				FatalErrorScreen(error: initializationError)
			} else {
				RootContainer()
					.handlesExternalEvents(preferring: Set(arrayLiteral: "Lattice"), allowing: Set(arrayLiteral: "*"))
			}
		}
		.handlesExternalEvents(matching: Set(arrayLiteral: "Lattice"))
	}
}
