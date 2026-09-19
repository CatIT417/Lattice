import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension EditableTextView {
	func updateModel() {
		model.update(
			blockId: blockId, originalText: originalText, font: ctFont as PlatformFont,
			handleAction: handleAction, onLinkClicked: onLinkClicked,
			onReferenceSuggestionCommand: onReferenceSuggestionCommand,
			onReferenceSuggestionContextChange: onReferenceSuggestionContextChange
		)
	}

	@MainActor final class Coordinator: NSObject {
		let model: EditableTextModel
		#if os(iOS)
		weak var tapHandler: UITapGestureRecognizer?
		#endif

		init(model: EditableTextModel) {
			self.model = model
			super.init()
			#if os(iOS)
			let notification = Notification.Name.appResignedActive
			#else
			let notification = NSApplication.didResignActiveNotification
			#endif
			NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive), name: notification, object: nil)
		}

		@objc private func appResignedActive() {
			model.appResignedActive()
		}
	}
}
