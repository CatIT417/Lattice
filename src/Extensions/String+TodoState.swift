import Foundation
import StructuredQueries

enum TodoState {
	case todo, done

	/// The raw prefix prepended to the block's string field.
	var prefix: String {
		switch self {
			case .todo: "{{[[TODO]]}} "
			case .done: "{{[[DONE]]}} "
		}
	}

	/// The UTF-16 length of the prefix (13 code units for both TODO and DONE).
	var prefixUTF16Length: Int {
		13
	}

	/// Flips TODO↔DONE.
	var toggled: TodoState {
		switch self {
			case .todo: .done
			case .done: .todo
		}
	}
}

extension TodoState? {
	/// Advances the state forward (TODO→DONE, DONE→nil).
	var next: TodoState? {
		switch self {
			case .none: .todo
			case .todo: .done
			case .done: nil
		}
	}
}

extension String {
	/// Detects whether this string starts with a TODO or DONE prefix.
	var todoState: TodoState? {
		if hasPrefix(TodoState.todo.prefix) { return .todo }
		if hasPrefix(TodoState.done.prefix) { return .done }
		return nil
	}

	/// Drops the TODO/DONE prefix if present.
	func strippingTodoPrefix() -> String {
		guard let state = todoState else { return self }
		return String(dropFirst(state.prefix.count))
	}

	/// The UTF-16 length of the TODO/DONE prefix, or 0 if none.
	var todoPrefixUTF16Length: Int {
		todoState?.prefixUTF16Length ?? 0
	}

	/// Returns the string with the given TODO state applied (stripping any existing prefix first).
	func withTodoState(_ state: TodoState?) -> String {
		let stripped = strippingTodoPrefix()
		guard let state else { return stripped }
		return state.prefix + stripped
	}
}

// MARK: - SQL Expression

extension QueryExpression where QueryValue: _OptionalProtocol, QueryValue.Wrapped == String {
	/// Transform an optional string column to the given TODO state.
	func withTodoState(_ state: TodoState?) -> SQLQueryExpression<String?> {
		let s = unsafelyUnwrapped
		let stripped = Case()
			.when(s.like("\(TodoState.todo.prefix)%"), then: s.substr(14))
			.when(s.like("\(TodoState.done.prefix)%"), then: s.substr(14))
			.else(s)

		guard let state else { return SQLQueryExpression("\(stripped)", as: String?.self) }
		return SQLQueryExpression("\(state.prefix + stripped)", as: String?.self)
	}
}
