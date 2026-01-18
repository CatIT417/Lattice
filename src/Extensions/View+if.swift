import SwiftUI

extension View {
	func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> AnyView {
		if condition { AnyView(transform(self)) }
		else { AnyView(self) }
	}
}
