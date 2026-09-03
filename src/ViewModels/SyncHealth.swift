import Foundation
import IssueReporting

/// Issues reported while the app runs, kept so the diagnostics screen can show them.
@MainActor @Observable
final class SyncHealth {
	struct Issue: Identifiable {
		let id = UUID()
		let date: Date
		let message: String

		/// SQLiteData reports CloudKit problems through `withErrorReporting` with this message.
		var isSyncFailure: Bool {
			message.contains("SQLiteData CloudKit Failure")
		}
	}

	static let shared = SyncHealth()
	static let retainedCount = 50

	private(set) var issueCount = 0
	private(set) var issues: [Issue] = []
	private(set) var syncFailureCount = 0

	func record(_ message: String) {
		let issue = Issue(date: Date(), message: message)

		issueCount += 1
		if issue.isSyncFailure { syncFailureCount += 1 }

		issues.append(issue)
		if issues.count > Self.retainedCount {
			issues.removeFirst(issues.count - Self.retainedCount)
		}
	}
}

/// Forwards every reported issue to `SyncHealth`.
struct SyncHealthIssueReporter: IssueReporter {
	func reportIssue(_ message: @autoclosure () -> String?, severity _: IssueSeverity, fileID _: StaticString, filePath: StaticString, line: UInt, column _: UInt) {
		record(message() ?? "Issue at \(filePath):\(line)")
	}

	func reportIssue(_ error: any Error, _ message: @autoclosure () -> String?, fileID _: StaticString, filePath _: StaticString, line _: UInt, column _: UInt) {
		record([message(), String(describing: error)].compactMap(\.self).joined(separator: ": "))
	}

	private func record(_ text: String) {
		Task { @MainActor in
			SyncHealth.shared.record(text)
		}
	}
}
