import SwiftUI
import SQLiteData

#if DEBUG
func previewData<T>(_ block: ((Database) throws -> T) = { _ in }) -> T {
	try! prepareDependencies {
		try $0.bootstrapDatabase()

		return try $0.defaultDatabase.read(block)
	}
}

fileprivate struct WrappedInNavigationModifier: ViewModifier {
	func body(content: Content) -> some View {
		NavigationContainer(parentRouter: .previewRouter()) {
			content
		}
	}
}

extension View {
	func preview(wrapInNavigation: Bool = true) -> some View {
		`if`(wrapInNavigation) { $0.modifier(WrappedInNavigationModifier()) }
	}
}
#else
func previewData<T>(_: (Database) throws -> T = { _ in }) -> T {
	fatalError("previewData is only available in DEBUG builds")
}

extension View {
	func preview(wrapInNavigation _: Bool = true) -> some View {
		self
	}
}
#endif
