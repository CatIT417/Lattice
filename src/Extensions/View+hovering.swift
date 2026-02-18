import SwiftUI

extension View {
	func hovering(_ binding: Binding<Bool>) -> some View {
		onHover { binding.wrappedValue = $0 }
	}
}
