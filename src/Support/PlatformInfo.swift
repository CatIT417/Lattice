import Foundation
import Dependencies
import GameController

@MainActor @Observable
final class PlatformInfo {
	var hasPointer: Bool

	private init() {
		hasPointer = GCMouse.current != nil

		NotificationCenter.default.addObserver(
			self, selector: #selector(mouseDidConnect), name: .GCMouseDidConnect, object: nil
		)

		NotificationCenter.default.addObserver(
			self, selector: #selector(mouseDidDisconnect), name: .GCMouseDidDisconnect, object: nil
		)
	}

	@objc private func mouseDidConnect() {
		hasPointer = true
	}

	@objc private func mouseDidDisconnect() {
		hasPointer = false
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
