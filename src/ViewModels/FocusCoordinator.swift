import SwiftUI

@MainActor @Observable
final class BlockCoordinator {
	enum RenderMode { case raw, rendered }

	private var cursorPosition: Int?
	private var focusedBlockId: Block.ID?
	private var renderMode: RenderMode = .rendered

	func request(for blockId: Block.ID, at position: Int? = nil, startingInMode mode: RenderMode = .rendered) {
		renderMode = mode
		focusedBlockId = blockId
		cursorPosition = position
	}

	func isActive(blockId: Block.ID?) -> Bool {
		guard let blockId else { return false }
		return focusedBlockId == blockId
	}

	func cursorPositionFor(blockId: Block.ID?) -> Int? {
		guard let blockId, focusedBlockId == blockId else { return nil }

		return cursorPosition
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
