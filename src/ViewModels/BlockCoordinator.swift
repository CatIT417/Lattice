import SwiftUI
import Dependencies

@MainActor @Observable
final class BlockCoordinator {
	enum RenderMode: Equatable, Hashable { case raw, rendered }
	enum PendingAction: Equatable, Hashable { case indent, outdent }

	enum CursorPlacement: Equatable, Hashable {
		/// Place cursor at a specific character offset
		case offset(Int)
		/// Place cursor at the visual X position (window coordinates) on the first or last line
		case visualX(CGFloat, edge: LineEdge)
	}

	enum LineEdge: Equatable, Hashable {
		case first // moving DOWN into this block
		case last // moving UP into this block
	}

	private var focusedBlock: Block.ID?

	private var cursorPlacement: CursorPlacement?
	private var isExpectingText: Bool = false
	private var pendingAction: PendingAction?
	private var renderMode: RenderMode = .rendered

	func request(for blockId: Block.ID?, at position: Int? = nil, expectsNewText: Bool = false, startingInMode mode: RenderMode = .rendered) {
		guard let blockId else { return }

		renderMode = mode
		focusedBlock = blockId
		cursorPlacement = position.map { .offset($0) }
		isExpectingText = expectsNewText
	}

	func request(for blockId: Block.ID?, visualX: CGFloat, edge: LineEdge, startingInMode mode: RenderMode = .rendered) {
		guard let blockId else { return }

		renderMode = mode
		focusedBlock = blockId
		isExpectingText = false
		cursorPlacement = .visualX(visualX, edge: edge)
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

	func cursorPlacementFor(blockId: Block.ID?) -> CursorPlacement? {
		guard let blockId, focusedBlock == blockId else { return nil }

		return cursorPlacement
	}

	func cursorPositionFor(blockId: Block.ID?) -> Int? {
		guard let blockId, focusedBlock == blockId, case let .offset(pos) = cursorPlacement else { return nil }

		return pos
	}

	func modeFor(blockId: Block.ID?) -> RenderMode? {
		guard let blockId, focusedBlock == blockId else { return nil }

		return renderMode
	}

	func clearFocus(for blockId: Block.ID?) {
		guard let blockId, focusedBlock == blockId, !isExpectingText else { return }

		focusedBlock = nil
		cursorPlacement = nil
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

extension BlockCoordinator: DependencyKey {
	static var liveValue = BlockCoordinator()
}

extension DependencyValues {
	var blockCoordinator: BlockCoordinator {
		get { self[BlockCoordinator.self] }
		set { self[BlockCoordinator.self] = newValue }
	}
}
