import SwiftUI

@MainActor @Observable
final class BlockCoordinator {
	enum RenderMode: Equatable, Hashable { case raw, rendered }
	enum PendingAction: Equatable, Hashable { case indent, outdent }

	private var focusedBlock: Block.ID?

	private var cursorPosition: Int?
	private var isExpectingText: Bool = false
	private var pendingAction: PendingAction?
	private var renderMode: RenderMode = .rendered

	func request(for blockId: Block.ID?, at position: Int? = nil, expectsNewText: Bool = false, startingInMode mode: RenderMode = .rendered) {
		guard let blockId else { return }

		renderMode = mode
		focusedBlock = blockId
		cursorPosition = position
		isExpectingText = expectsNewText
	}

	func shouldFocus(blockId: Block.ID?) -> Bool {
		guard let blockId else { return false }
		return focusedBlock == blockId
	}

	func expectsNewText(for blockId: Block.ID?) -> Bool {
		guard let focusedBlock, focusedBlock == blockId else { return false }
		return isExpectingText
	}

	func shouldQueueActions(blockId: Block.ID?) -> Bool {
		guard let focusedBlock, let blockId else { return false }
		return focusedBlock != blockId
	}

	func cursorPositionFor(blockId: Block.ID?) -> Int? {
		guard let blockId, focusedBlock == blockId else { return nil }

		return cursorPosition
	}

	func modeFor(blockId: Block.ID?) -> RenderMode? {
		guard let blockId, focusedBlock == blockId else { return nil }

		return renderMode
	}

	func clearFocus(for blockId: Block.ID?) {
		guard let blockId, focusedBlock == blockId, !isExpectingText else { return }

		focusedBlock = nil
		cursorPosition = nil
		renderMode = .rendered
	}

	func textReceived(for blockId: Block.ID?) {
		guard let blockId, focusedBlock == blockId, isExpectingText else { return }

		isExpectingText = false
		clearFocus(for: blockId)
	}

	func queueAction(_ action: PendingAction) {
		pendingAction = action
	}

	func popAction(for blockId: Block.ID?) -> PendingAction? {
		guard let blockId, focusedBlock == blockId, let action = pendingAction else { return nil }

		pendingAction = nil
		return action
	}
}

extension EnvironmentValues {
	@Entry var blockCoordinator: BlockCoordinator?
}
