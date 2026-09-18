import Testing
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/Range+contains")
	struct RangeContainsTest {}
}

extension Tests.RangeContainsTest {
	@Test("Range containment includes its empty boundaries", arguments: [
		(0..<10, true), (2..<8, true), (0..<5, true), (5..<10, true),
		(-1..<5, false), (8..<12, false), (0..<0, true), (5..<5, true), (10..<10, true),
	])
	func containsRange(inner: Range<Int>, expected: Bool) {
		expectNoDifference((0..<10).contains(inner), expected)
	}
}
