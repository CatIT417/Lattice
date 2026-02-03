import Foundation

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
