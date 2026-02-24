import Foundation

/// Clamps a value to the provided bounds.
func clamp<T: Comparable>(_ value: T, to bounds: ClosedRange<T>) -> T {
	min(max(value, bounds.lowerBound), bounds.upperBound)
}

/// Call the given Closure with the given value then return the value.
func tap<T, E>(_ value: T, _ block: (inout T) throws(E) -> Void) throws(E) -> T {
	var value = value
	try block(&value)
	return value
}

/// Call the given Closure with the given value.
func tap<T, E>(_ value: inout T, _ block: (inout T) throws(E) -> Void) throws(E) {
	try block(&value)
}

/// Call the given Closure with the given value then return the value.
func tap<T, E>(_ value: T, _ block: (inout T) async throws(E) -> Void) async throws(E) -> T {
	var value = value
	try await block(&value)
	return value
}

/// Call the given Closure with the given value then return the result.
func with<T, E, R>(_ value: T, _ block: (inout T) throws(E) -> R) throws(E) -> R {
	var copy = value
	return try block(&copy)
}

/// Call the given Closure with the given value then return the result.
func with<T, E, R>(_ value: T, _ block: (inout T) async throws(E) -> R) async throws(E) -> R {
	var copy = value
	return try await block(&copy)
}

/// Applies a rubber band effect to an offset value.
func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
	let sign: CGFloat = offset < 0 ? -1 : 1
	let absOffset = abs(offset)

	return sign * limit * (1 - 1 / (absOffset / limit + 1))
}
