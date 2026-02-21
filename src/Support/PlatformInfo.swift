import Foundation
import Dependencies
import GameController

@MainActor @Observable
final class PlatformInfo {
	var hasPointer: Bool
	var hasKeyboard: Bool

	private init() {
		hasPointer = GCMouse.current != nil
		hasKeyboard = GCKeyboard.coalesced != nil

		NotificationCenter.default.addObserver(
			self, selector: #selector(mouseDidConnect), name: .GCMouseDidConnect, object: nil
		)

		NotificationCenter.default.addObserver(
			self, selector: #selector(keyboardDidConnect), name: .GCKeyboardDidConnect, object: nil
		)

		NotificationCenter.default.addObserver(
			self, selector: #selector(mouseDidDisconnect), name: .GCMouseDidDisconnect, object: nil
		)

		NotificationCenter.default.addObserver(
			self, selector: #selector(keyboardDidDisconnect), name: .GCKeyboardDidDisconnect, object: nil
		)
	}

	@objc private func mouseDidConnect() {
		hasPointer = true
	}

	@objc private func keyboardDidConnect() {
		hasKeyboard = true
	}

	@objc private func mouseDidDisconnect() {
		hasPointer = false
	}

	@objc private func keyboardDidDisconnect() {
		hasKeyboard = false
	}
}

// MARK: - Dependency Setup

extension PlatformInfo: DependencyKey {
	static let liveValue = PlatformInfo()
}

extension DependencyValues {
	var platform: PlatformInfo {
		get { self[PlatformInfo.self] }
		set { self[PlatformInfo.self] = newValue }
	}
}
