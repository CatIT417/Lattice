#if os(iOS)
import SwiftUI

extension Notification.Name {
	static let appResignedActive = Notification.Name("appResignedActive")
}

struct PostNotificationOnStateChangeModifier: ViewModifier {
	@Environment(\.scenePhase) private var scenePhase

	func body(content: Content) -> some View {
		content.onChange(of: scenePhase) { oldPhase, newPhase in
			if oldPhase == .active && newPhase != .active {
				NotificationCenter.default.post(name: .appResignedActive, object: nil)
			}
		}
	}
}

extension View {
	func postNotificationOnStateChange() -> some View {
		modifier(PostNotificationOnStateChangeModifier())
	}
}
#endif
