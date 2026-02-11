#if os(macOS)
import AppKit
import SwiftUI

struct ClearInitialResponderOnLaunchModifier: ViewModifier {
	@State private var didResetInitialResponderOnFirstKey = false

	func body(content: Content) -> some View {
		content

			.background(
				OnWindowKeyed { window in
					guard !didResetInitialResponderOnFirstKey else { return }
					didResetInitialResponderOnFirstKey = true

					window.initialFirstResponder = nil
					_ = window.makeFirstResponder(nil)
				}
			)
	}
}

extension View {
	func clearInitialResponderOnLaunch() -> some View {
		modifier(ClearInitialResponderOnLaunchModifier())
	}
}

fileprivate struct OnWindowKeyed: NSViewRepresentable {
	var onWindowDidBecomeKey: (NSWindow) -> Void

	func makeNSView(context _: Context) -> WindowObserverView {
		let view = WindowObserverView()
		view.onWindowDidBecomeKey = onWindowDidBecomeKey
		return view
	}

	func updateNSView(_ nsView: WindowObserverView, context _: Context) {
		nsView.onWindowDidBecomeKey = onWindowDidBecomeKey
		nsView.notifyIfNeeded()
	}

	final class WindowObserverView: NSView {
		var onWindowDidBecomeKey: ((NSWindow) -> Void)?
		private weak var deliveredWindow: NSWindow?
		private var observers: [NSObjectProtocol] = []

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			notifyIfNeeded()
		}

		func notifyIfNeeded() {
			guard let window, deliveredWindow !== window else { return }
			deliveredWindow = window
			registerWindowObservers(for: window)
			if window.isKeyWindow {
				onWindowDidBecomeKey?(window)
			}
		}

		private func registerWindowObservers(for window: NSWindow) {
			for observer in observers {
				NotificationCenter.default.removeObserver(observer)
			}
			observers.removeAll()

			observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated {
					self?.onWindowDidBecomeKey?(window)
				}
			})
		}
	}
}
#endif
