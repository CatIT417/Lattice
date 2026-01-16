import OSLog
import Foundation
import IssueReporting

struct Logger: Sendable {
	static let app = Logger(category: "App")

	private let category: String
	private let logger: os.Logger

	init(category: String) {
		self.category = category
		logger = os.Logger(subsystem: Bundle.main.bundleIdentifier!, category: category)
	}

	private func log(_ message: String, level: Level) {
		if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
			print("\(level.emoji) [\(category)] \(message)")
		}

		switch level {
			case .debug:
				logger.debug("\(message)")
			case .info:
				logger.info("\(message)")
			case .warning:
				logger.warning("\(message)")
			case .error:
				logger.error("\(message)")
			case .fatal:
				logger.fault("\(message)")
			default:
				logger.info("\(message)")
		}
	}

	func debug(_ message: String) {
		log(message, level: .debug)
	}

	func info(_ message: String) {
		log(message, level: .info)
	}

	func warning(_ message: String) {
		log(message, level: .warning)
	}

	func error(_ message: String) {
		log(message, level: .error)
	}

	func fault(_ message: String) {
		log(message, level: .fatal)
	}
}

enum Level {
	case trace, debug, info, warning, error, fatal

	var emoji: String {
		switch self {
			case .info: "ℹ️"
			case .debug: "🐛"
			case .error: "❗️"
			case .fatal: "💀"
			case .trace: "🔍"
			case .warning: "⚠️"
		}
	}
}

struct OSLogIssueReporter: IssueReporter {
	func reportIssue(_ message: @autoclosure () -> String?, fileID _: StaticString, filePath: StaticString, line: UInt, column _: UInt) {
		Logger.app.error(message() ?? "Unexpected developer error in \(filePath):\(line)")
	}

	func reportIssue(_ error: any Error, _ message: @autoclosure () -> String?, fileID _: StaticString, filePath: StaticString, line: UInt, column _: UInt) {
		Logger.app.error(message() ?? "Unexpected developer error in \(filePath):\(line) \(error)")
	}
}
