import Foundation
import SQLiteData

@DatabaseFunction
nonisolated func containsOutsideRefs(_ text: String, _ title: String) -> Bool {
	var stripped = text
	for ref in text.extractRefs().sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
		stripped.removeSubrange(ref.range)
	}
	return stripped.localizedCaseInsensitiveContains(title)
}
