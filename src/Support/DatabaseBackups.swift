import GRDB
import os.lock
import Foundation
import SQLiteData

fileprivate nonisolated let logger = Logger(category: "Backups")

/// Keeps a rolling set of daily copies of the database in a `Backups` folder next to it.
enum DatabaseBackups {
	static let retainedCount = 7
	private static let lock = OSAllocatedUnfairLock()

	/// Creates today's backup if it does not exist yet (or unconditionally when `force` is set) and prunes old ones.
	static func backup(force: Bool = false) {
		@Dependency(\.context) var context
		guard context == .live else { return }

		lock.lock()
		defer { lock.unlock() }

		withErrorReporting {
			let directory = try directory()
			let destination = directory.appending(path: "lattice-\(DayOfYear.today.rawValue).sqlite")

			for leftover in try contents(of: directory) where leftover.pathExtension == "tmp" {
				try FileManager.default.removeItem(at: leftover)
			}

			if force || !FileManager.default.fileExists(atPath: destination.path) {
				try copyDatabase(to: destination)
				logger.info("backed up database to \(destination.lastPathComponent)")
			}

			for stale in try existingBackups().dropFirst(retainedCount) {
				try FileManager.default.removeItem(at: stale)
			}
		}
	}

	/// Existing backups, newest first.
	static func existingBackups() throws -> [URL] {
		try contents(of: directory())
			.filter { $0.pathExtension == "sqlite" }
			.sorted { $0.lastPathComponent > $1.lastPathComponent }
	}

	private static func copyDatabase(to destination: URL) throws {
		@Dependency(\.defaultDatabase) var database

		let temporary = destination.appendingPathExtension("\(UUID().uuidString).tmp")

		do {
			try database.backup(to: DatabaseQueue(path: temporary.path))

			if FileManager.default.fileExists(atPath: destination.path) {
				_ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
			} else {
				try FileManager.default.moveItem(at: temporary, to: destination)
			}
		} catch {
			try? FileManager.default.removeItem(at: temporary)
			throw error
		}
	}

	private static func contents(of directory: URL) throws -> [URL] {
		try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
	}

	private static func directory() throws -> URL {
		@Dependency(\.defaultDatabase) var database

		let databaseURL = URL(string: database.path)!

		let directory = databaseURL
			.deletingLastPathComponent()
			.appending(path: Bundle.main.bundleIdentifier ?? "Lattice", directoryHint: .isDirectory)
			.appending(path: "Backups", directoryHint: .isDirectory)

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		return directory
	}
}
