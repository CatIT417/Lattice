import Testing
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/Range+contains")
	struct RangeContainsTest {}
}

extension Tests.RangeContainsTest {
	@Test("Range.contains returns true for contained ranges")
	func containsRange() {
		let outer = 0..<10

		expectNoDifference(true, outer.contains(0..<10))
		expectNoDifference(true, outer.contains(0..<5))
		expectNoDifference(true, outer.contains(5..<10))
	}

	@Test("Range.contains returns false for overlapping or out-of-bounds ranges")
	func doesNotContainRange() {
		let outer = 0..<10

		expectNoDifference(false, outer.contains((-1)..<5))
		expectNoDifference(false, outer.contains(8..<12))
		expectNoDifference(false, outer.contains(5..<11))
	}

	@Test("Range.contains treats empty ranges inside bounds as contained")
	func containsEmptyRange() {
		let outer = 0..<10

		expectNoDifference(true, outer.contains(5..<5))
	}
}
