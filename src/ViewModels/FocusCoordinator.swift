import SwiftUI

@MainActor @Observable
final class BlockCoordinator {
	enum RenderMode { case raw, rendered }

	private(set) var cursorPosition: Int?
	private(set) var focusedBlockId: Block.ID?
	private(set) var renderMode: RenderMode = .rendered

	func request(for blockId: Block.ID, at position: Int? = nil, startingInMode mode: RenderMode = .rendered) {
		renderMode = mode
		focusedBlockId = blockId
		cursorPosition = position
	}

	func isActive(blockId: Block.ID?) -> Bool {
		guard let blockId else { return false }
		return focusedBlockId == blockId
	}

	func modeFor(blockId: Block.ID?) -> RenderMode? {
		guard let blockId, focusedBlockId == blockId else { return nil }

		return renderMode
	}

	func clear(for blockId: Block.ID?) {
		guard let blockId, focusedBlockId == blockId else { return }

		focusedBlockId = nil
		cursorPosition = nil
		renderMode = .rendered
	}
}

extension EnvironmentValues {
	@Entry var blockCoordinator: BlockCoordinator?
}
