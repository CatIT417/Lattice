import Testing
import Foundation
@testable import LatticeDev
import SQLiteData
import Dependencies
import DependenciesTestSupport

// MARK: - Base Test Suite

@Suite(.dependencies {
	$0.uuid = .incrementing
	$0.date = .constant(Date(timeIntervalSince1970: 1_000))
	$0.locale = Locale(identifier: "en_US")
})
struct Tests {}

// MARK: - Test Helpers

import CustomDump
import InlineSnapshotTesting

public extension Snapshotting where Value == NSAttributedString, Format == String {
	static var raw: Snapshotting {
		return SimplySnapshotting.lines.pullback { $0.snapshotDescription }
	}
}
