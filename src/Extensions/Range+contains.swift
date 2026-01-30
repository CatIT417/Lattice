import Foundation

extension Range {
	func contains(_ range: Range<Bound>) -> Bool {
		range.lowerBound >= lowerBound && range.upperBound <= upperBound
	}
}
