#if os(iOS)
import SwiftUI
import Dependencies

@MainActor @Observable
final class BlockSelectionCoordinator {
	private(set) var highlightedIDs: Set<Block.ID> = []

	var animation: Animation {
		.easeInOut(duration: 0.2)
	}

	var hasSelection: Bool {
		!highlightedIDs.isEmpty
	}

	func isHighlighted(_ blockID: Block.ID) -> Bool {
		highlightedIDs.contains(blockID)
	}

	func toggleSelection(on blockID: Block.ID) {
		if highlightedIDs.contains(blockID) { highlightedIDs.remove(blockID) }
		else { highlightedIDs.insert(blockID) }
	}

	func handleSwipe(on blockID: Block.ID, descendantIDs: Set<Block.ID>) {
		guard highlightedIDs.contains(blockID) else {
			highlightedIDs.insert(blockID)
			return
		}

		guard descendantIDs.isEmpty || descendantIDs.isSubset(of: highlightedIDs) else {
			highlightedIDs.formUnion(descendantIDs)
			return
		}

		highlightedIDs.remove(blockID)
		highlightedIDs.subtract(descendantIDs)
	}

	func clearSelection() {
		highlightedIDs = []
	}
}

// MARK: - Dependency Setup

extension BlockSelectionCoordinator: DependencyKey {
	static var liveValue = BlockSelectionCoordinator()
}

extension DependencyValues {
	var blockSelectionCoordinator: BlockSelectionCoordinator {
		get { self[BlockSelectionCoordinator.self] }
		set { self[BlockSelectionCoordinator.self] = newValue }
	}
}
#endif
