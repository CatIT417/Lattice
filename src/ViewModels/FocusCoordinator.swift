import SwiftUI

@MainActor @Observable
final class FocusCoordinator {
	private(set) var focusedBlockId: Block.ID?

	func requestFocus(for blockId: Block.ID) {
		focusedBlockId = blockId
	}

	func clearFocus() {
		focusedBlockId = nil
	}
}

extension EnvironmentValues {
	@Entry var focusCoordinator: FocusCoordinator?
}
