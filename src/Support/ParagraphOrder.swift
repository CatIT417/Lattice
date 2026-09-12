import Foundation
import SQLiteData

struct ParagraphOrder {
	static let gap = 1 << 32

	enum Direction {
		case up, down
	}

	enum Error: Swift.Error {
		case missingSibling
	}

	/// The original parent ID of the paragraph being reordered, along with any parent IDs of pages merged into it.
	private let rawParentIDs: [Block.ID]

	/// All paragraphs that are siblings of the paragraph being reordered, including those in merged pages.
	private var rawSiblings: Where<Block> {
		Block.where { $0.parentId.unsafelyUnwrapped.in(rawParentIDs) }
	}

	init(parentId: Block.ID, in db: Database) throws {
		rawParentIDs = try With {
			SiblingParent(id: parentId)
				.union(
					Block.where(\.isPage)
						.join(SiblingParent.all) { blocks, parents in blocks.mergedInto.eq(parents.id) }
						.select { blocks, _ in SiblingParent.Columns(id: blocks.id) }
				)
		} query: {
			SiblingParent.select(\.id)
		}.fetchAll(db)
	}

	/// Find an `order` value for a new sibling that will place it before the given sibling, or at the end of the list if no sibling is provided.
	///
	/// - Parameter siblingId: The ID of the sibling to place the new sibling before, or `nil` to place it at the end of the list.
	/// - Parameter movingId: The ID of the sibling being moved, if any, to exclude it from the calculation.
	/// - Parameter db: The database connection to use for the query
	func rank(before siblingId: Block.ID? = nil, excluding movingId: Block.ID? = nil, in db: Database) throws -> Int {
		let right = try siblingId.map { try position(of: $0, in: db) }
		return try rank(beforePosition: right, excluding: movingId, in: db)
	}

	/// Find an `order` value for a new sibling that will place it after the given sibling, or at the beginning of the list if no sibling is provided.
	///
	/// - Parameter siblingId: The ID of the sibling to place the new sibling after, or `nil` to place it at the beginning of the list.
	/// - Parameter movingId: The ID of the sibling being moved, if any, to exclude it from the calculation.
	/// - Parameter db: The database connection to use for the query
	func rank(after siblingId: Block.ID?, excluding movingId: Block.ID? = nil, in db: Database) throws -> Int {
		let anchor = try siblingId.map { try position(of: $0, in: db) }
		let right = try visibleNeighbors(anchor: anchor, direction: .down, limit: 1, in: db).first
		return try rank(beforePosition: right, excluding: movingId, in: db)
	}

	/// Find `order` values for a given number of new siblings that will place them at the end of the list.
	///
	/// - Parameter count: The number of new siblings to place at the end of the list.
	/// - Parameter db: The database connection to use for the query
	/// - Returns: An array of `order` values for the new siblings
	func appendRanks(count: Int, in db: Database) throws -> [Int] {
		guard count > 0 else { return [] }

		// find the largest `order` value among the siblings. if there are none, fall back to `-gap` so the first `order` becomes 0
		let base = try rawSiblings
			.order { $0.order.desc() }
			.limit(1)
			.select(\.order)
			.fetchOne(db) ?? -Self.gap

		// if there is enough space to add `count` new siblings without overflowing, return the new `order` values
		let (distance, distanceOverflow) = Self.gap.multipliedReportingOverflow(by: count)
		if !distanceOverflow, !base.addingReportingOverflow(distance).overflow {
			return (1 ... count).map { base + $0 * Self.gap }
		}

		// otherwise, renumber the siblings to make space
		let siblings = try rawSiblings
			.order { ($0.order, $0.id) }
			.select { SiblingPosition.Columns(order: $0.order, id: $0.id) }
			.fetchAll(db)
		return try Self.renumber(for: count, at: siblings.count, among: siblings, in: db)
	}

	/// Move a paragraph up or down in the order of its (visible) siblings.
	///
	/// - Parameter id: The ID of the paragraph to move.
	/// - Parameter direction: The direction to move the paragraph.
	/// - Parameter db: The database connection to use for the query.
	/// - Returns: `true` if the paragraph was moved, `false` otherwise.
	static func move(_ id: Paragraph.ID, direction: Direction, in db: Database) throws -> Bool {
		guard let (parentId, order) = try Paragraph.find(id).select({ ($0.parentId, $0.order) }).fetchOne(db) else { return false }

		let ordering = try Self(parentId: parentId, in: db)
		let anchor = SiblingPosition(order: order, id: id)
		let next: SiblingPosition?
		switch direction {
			case .up:
				guard let previous = try ordering.visibleNeighbors(anchor: anchor, direction: .up, limit: 1, in: db).first else { return false }
				next = previous
			case .down:
				let siblings = try ordering.visibleNeighbors(anchor: anchor, direction: .down, limit: 2, in: db)
				guard !siblings.isEmpty else { return false }
				next = siblings.dropFirst().first
		}

		let rank = try ordering.rank(beforePosition: next, excluding: id, in: db)
		try Block.find(id)
			.update {
				$0.order = #bind(rank)
				$0.parentId = #bind(parentId)
			}
			.execute(db)

		return true
	}

	/// Get the `order` of a given sibling
	///
	/// - Parameter id: The ID of the sibling to get the order of
	/// - Parameter db: The database connection to use for the query
	/// - Returns: The `SiblingPosition` of the sibling with the given ID
	/// - Throws: `Error.missingSibling` if the sibling with the given ID does not exist
	private func position(of id: Block.ID, in db: Database) throws -> SiblingPosition {
		let position = try rawSiblings.where { $0.id.eq(id) }
			.select { SiblingPosition.Columns(order: $0.order, id: $0.id) }
			.fetchOne(db)
		guard let position else { throw Error.missingSibling }
		return position
	}

	/// Find an `order` value for a new sibling that will place it before the given sibling position, or at the end of the list if no sibling is provided.
	///
	/// - Parameter right: The position of the sibling to place the new sibling before, or `nil` to place it at the end of the list.
	/// - Parameter movingId: The ID of the sibling being moved, if any, to exclude it from the calculation.
	/// - Parameter db: The database connection to use for the query
	/// - Returns: The `order` value for the new sibling
	private func rank(beforePosition right: SiblingPosition?, excluding movingId: Block.ID?, in db: Database) throws -> Int {
		// exclude `movingId` from queries if present
		var query = rawSiblings
		if let movingId {
			guard right?.id != movingId else { throw Error.missingSibling }
			query = query.where { $0.id.neq(movingId) }
		}

		// limit query to siblings before `right` if present
		var previous = query
		if let right {
			previous = previous.where { SiblingPosition.Columns(order: $0.order, id: $0.id).lt(right) }
		}

		// find the `order` of the sibling immediately before `right`, if any
		let left = try previous.order { $0.order.desc() }.limit(1).select(\.order).fetchOne(db)
		// if there is space between `left` and `right`, return the midpoint
		if let rank = Self.between(left, right?.order) { return rank }

		// we couldn't find a gap, so we need to renumber the siblings to make space
		let siblings = try query.order { ($0.order, $0.id) }
			.select { SiblingPosition.Columns(order: $0.order, id: $0.id) }
			.fetchAll(db)
		let index = right.flatMap { right in siblings.firstIndex { $0.id == right.id } } ?? siblings.count
		return try Self.renumber(for: 1, at: index, among: siblings, in: db)[0]
	}

	/// Find visible siblings in the given direction from the given anchor, up to the given limit.
	///
	/// - Parameter anchor: The position of the sibling to start from, or `nil` to start from the beginning or end of the list.
	/// - Parameter direction: The direction to search in.
	/// - Parameter limit: The maximum number of siblings to return.
	/// - Parameter db: The database connection to use for the query.
	/// - Returns: An array of `SiblingPosition` values for the visible siblings in the given direction from the given anchor, up to the given limit.
	private func visibleNeighbors(anchor: SiblingPosition?, direction: Direction, limit: Int, in db: Database) throws -> [SiblingPosition] {
		var candidates: [SiblingPosition] = []

		for parent in rawParentIDs {
			var query = Block.where { $0.parentId.eq(parent) && $0.isParagraph }

			if let anchor {
				query = query.where {
					let position = SiblingPosition.Columns(order: $0.order, id: $0.id)
					if direction == .down { position.gt(anchor) }
					else { position.lt(anchor) }
				}
			}

			candidates += try query.order {
				if direction == .down { ($0.order, $0.id) }
				else { ($0.order.desc(), $0.id.desc()) }
			}
			.join(BlockHierarchy.all) { $0.id.eq($1.blockId) && $1.isVisible }
			.select { blocks, _ in SiblingPosition.Columns(order: blocks.order, id: blocks.id) }
			.limit(limit)
			.fetchAll(db)
		}

		return Array(candidates.sorted { direction == .down ? $0 < $1 : $1 < $0 }.prefix(limit))
	}

	/// Renumber the given siblings to make space for `count` new siblings at the given index, and return the new `order` values for those new siblings.
	///
	/// - Parameter count: The number of new siblings to make space for.
	/// - Parameter index: The index at which to insert the new siblings.
	/// - Parameter siblings: The siblings to renumber.
	/// - Parameter db: The database connection to use for the query.
	private static func renumber(for count: Int, at index: Int, among siblings: [SiblingPosition], in db: Database) throws -> [Int] {
		let spacing = min(gap, Int.max / (siblings.count + count))

		for (offset, block) in siblings.enumerated() {
			let order = (offset < index ? offset : offset + count) * spacing
			if block.order != order {
				try Block.find(block.id).update { $0.order = #bind(order) }.execute(db)
			}
		}

		return (index ..< index + count).map { $0 * spacing }
	}

	/// Find a gap between two `Int` values, or return `nil` if there is none.
	///
	/// - Parameter left: The left value, or `nil` if there is none.
	/// - Parameter right: The right value, or `nil` if there is none.
	static func between(_ left: Int?, _ right: Int?) -> Int? {
		switch (left, right) {
			// there is no left or right value, so we can return 0
			case (nil, nil): return 0
			// there is no right value, so we can return left + gap (unless it overflows)
			case let (left?, nil):
				let (value, overflow) = left.addingReportingOverflow(gap)
				return overflow ? nil : value
			// there is no left value, so we can return right - gap (unless it overflows)
			case let (nil, right?):
				let (value, overflow) = right.subtractingReportingOverflow(gap)
				return overflow ? nil : value
			// find the midpoint between left and right, if there is space
			case let (left?, right?):
				guard left < right, left < right - 1 else { return nil }
				return (left & right) + ((left ^ right) >> 1)
		}
	}
}

fileprivate extension ParagraphOrder {
	@Selection struct SiblingParent {
		let id: Block.ID
	}

	@Selection struct SiblingPosition: Comparable {
		let order: Int
		let id: Block.ID

		static func < (lhs: Self, rhs: Self) -> Bool {
			(lhs.order, lhs.id.uuidString) < (rhs.order, rhs.id.uuidString)
		}
	}
}
