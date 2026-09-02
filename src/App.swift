import SwiftUI
import SQLiteData
#if !DEBUG && canImport(Sentry)
import Sentry
#endif

@main
struct LatticeApp: App {
	var initializationError: (any Error)?

	init() {
		#if DEBUG
		UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
		#elseif canImport(Sentry)
		SentrySDK.start { options in
			options.enableLogs = true
			options.sendDefaultPii = true
			#if os(iOS)
			options.attachScreenshot = true
			options.attachViewHierarchy = true
			options.sessionReplay.quality = .low
			options.sessionReplay.maskAllText = false
			options.sessionReplay.maskAllImages = false
			options.sessionReplay.onErrorSampleRate = 1.0
			options.sessionReplay.sessionSampleRate = 0.1
			options.screenshot = SentryViewScreenshotOptions(maskAllText: false, maskAllImages: false)
			#endif
			options.enableAutoSessionTracking = true
			options.dsn = "https://296e9abf10b15af57e543fe72127f224@o85760.ingest.us.sentry.io/4510864994795520"
		}
		#endif

		#if !DEBUG
		IssueReporters.current = IssueReporters.current + [OSLogIssueReporter()]
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
		.commands {
			SidebarCommands()
		}
	}
}
