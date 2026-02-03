import Testing
import Foundation
import SQLiteData
import Dependencies
import DependenciesTestSupport

@testable import LatticeDev

// MARK: - Base Test Suite

@Suite(.dependencies {
	$0.uuid = .incrementing
	$0.date = .init { Date() }

	try $0.bootstrapDatabase()
})
struct Tests {}

// MARK: - Test Helpers

import CustomDump
import InlineSnapshotTesting

func expectDifference<T: Equatable>(
	_ expression: @autoclosure () -> FetchAll<T>,
	_ message: @autoclosure () -> String? = nil,
	operation: () async throws -> Void,
	changes: (inout [T]) throws -> Void,
	fileID: StaticString = #fileID,
	filePath: StaticString = #filePath,
	line: UInt = #line,
	column: UInt = #column
) async {
	let expression = expression()

	await expectDifference(expression.wrappedValue, message(), operation: {
		try await operation()
		try await expression.load()
	}, changes: changes, fileID: fileID, filePath: filePath, line: line, column: column)
}

public extension Snapshotting where Value == NSAttributedString, Format == String {
	static var raw: Snapshotting {
		return SimplySnapshotting.lines.pullback { $0.snapshotDescription }
	}
}
