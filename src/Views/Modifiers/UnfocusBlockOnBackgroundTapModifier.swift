import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct UnfocusBlockOnBackgroundTapModifier: ViewModifier {
	func body(content: Content) -> some View {
		content
			.contentShape(Rectangle())
			.simultaneousGesture(TapGesture().onEnded(unfocus), including: .gesture)
	}

	private func unfocus() {
		#if os(macOS)
		(NSApp.keyWindow ?? NSApp.mainWindow)?.makeFirstResponder(nil)
		#elseif os(iOS)
		guard UIDevice.current.userInterfaceIdiom == .pad else { return }
		UIApplication.shared.dismissKeyboard()
		#endif
	}
}

extension View {
	func unfocusBlockOnBackgroundTap() -> some View {
		modifier(UnfocusBlockOnBackgroundTapModifier())
	}
}
