import OSLog
import Foundation
import IssueReporting
#if !DEBUG && canImport(Sentry)
import Sentry
#endif

struct Logger: Sendable {
	static let app = Logger(category: "App")

	private let category: String
	private let logger: os.Logger

	init(category: String) {
		self.category = category
		logger = os.Logger(subsystem: Bundle.main.bundleIdentifier!, category: category)
	}

	private func log(_ message: String, level: Level, error: (any Error)? = nil) {
		if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
			print("\(level.emoji) [\(category)] \(message)")
		}

		switch level {
			case .debug:
				logger.debug("\(message)")
				#if !DEBUG && canImport(Sentry)
				SentrySDK.logger.debug(message)
				#endif
			case .info:
				logger.info("\(message)")
				#if !DEBUG && canImport(Sentry)
				SentrySDK.logger.info(message)
				#endif
			case .warning:
				logger.warning("\(message)")
				#if !DEBUG && canImport(Sentry)
				SentrySDK.logger.warn(message)
				#endif
			case .error:
				logger.error("\(message)")
				#if !DEBUG && canImport(Sentry)
				SentrySDK.logger.error(message)
				if let error { SentrySDK.capture(error: error) }
				#endif
			case .fatal:
				logger.fault("\(message)")
				#if !DEBUG && canImport(Sentry)
				SentrySDK.logger.fatal(message)
				if let error { SentrySDK.capture(error: error) }
				#endif
			default:
				logger.info("\(message)")
				#if !DEBUG && canImport(Sentry)
				SentrySDK.logger.info(message)
				#endif
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

	func error(_ message: String, error: (any Error)? = nil) {
		log(message, level: .error, error: error)
	}

	func fault(_ message: String, error: (any Error)? = nil) {
		log(message, level: .fatal, error: error)
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
		Logger.app.error(message() ?? "Unexpected developer error in \(filePath):\(line) \(error)", error: error)
	}
}
