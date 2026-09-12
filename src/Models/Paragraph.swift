import Foundation
import SQLiteData

@Table
struct Paragraph: Identifiable, Equatable, Hashable, Codable, Sendable, HasChildren {
	/// Internal entity ID (like Roam's e-id)
	let id: UUID

	/// Block text content
	var string: String

	/// ID of parent block
	var parentId: Block.ID

	/// Root page for this block
	let pageId: Page.ID

	/// Position among siblings
	var order: Int = 0

	/// 1, 2, or 3 (NULL = normal)
	var heading: Block.HeadingLevel? = nil

	/// 'bullet', 'document', 'numbered'
	var viewType: Block.ViewType = .bullet

	/// 'left', 'center', 'right', 'justify'
	var textAlign: Block.TextAlignment = .left

	/// Collapsed state
	var isOpen: Bool = true

	/// JSON blob for extensible data
	var props: String? = nil

	var createdAt: Date
	var updatedAt: Date

	var parentIsPage: Bool {
		parentId == pageId
	}

	init(id: UUID? = nil, string: String, parentId: Block.ID, pageId: Page.ID, order: Int, heading: Block.HeadingLevel? = nil, viewType: Block.ViewType = .bullet, textAlign: Block.TextAlignment = .left, isOpen: Bool = true, props: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
		@Dependency(\.uuid) var uuid
		@Dependency(\.date.now) var now

		self.props = props
		self.order = order
		self.string = string
		self.isOpen = isOpen
		self.pageId = pageId
		self.id = id ?? uuid()
		self.heading = heading
		self.viewType = viewType
		self.parentId = parentId
		self.textAlign = textAlign
		self.createdAt = createdAt ?? now
		self.updatedAt = updatedAt ?? now
	}

	init?(block: Block, pageId: Page.ID) {
		guard let string = block.string, let parentId = block.parentId else {
			return nil
		}

		id = block.id
		props = block.props
		order = block.order
		self.string = string
		self.pageId = pageId
		isOpen = block.isOpen
		heading = block.heading
		self.parentId = parentId
		viewType = block.viewType
		textAlign = block.textAlign
		createdAt = block.createdAt
		updatedAt = block.updatedAt
	}
}

extension Paragraph {
	/// The given paragraphs plus every paragraph nested underneath them.
	static func subtrees(rootedAt ids: [Paragraph.ID]) -> Where<Paragraph> {
		Paragraph.where {
			$0.id.in(ids) || $0.id.in(Ancestor.select(\.blockId).where { $0.ancestorId.in(ids) })
		}
	}

	static func fetchInOrder(_ blockIDs: Set<Paragraph.ID>) throws -> [Paragraph] {
		@Dependency(\.defaultDatabase) var database

		return try database.read { db in
			let paragraphs = try Paragraph
				.where {
					$0.id.in(blockIDs) || $0.id.in(Ancestor.where { $0.blockId.in(blockIDs) }.select(\.ancestorId))
				}
				.join(Page.all) { $0.pageId.eq($1.id) }
				.order { paragraphs, pages in (pages.createdAt.desc(), pages.id, paragraphs.order, paragraphs.id) }
				.select { paragraphs, _ in paragraphs }
				.fetchAll(db)

			var result: [Paragraph] = []
			let children = Dictionary(grouping: paragraphs, by: \.parentId)
			var stack = Array(paragraphs.filter(\.parentIsPage).reversed())

			while let paragraph = stack.popLast() {
				if blockIDs.contains(paragraph.id) { result.append(paragraph) }
				stack.append(contentsOf: (children[paragraph.id] ?? []).reversed())
			}

			return result
		}
	}

	static func ordered(_ lhs: Paragraph, _ rhs: Paragraph) -> Bool {
		lhs.order == rhs.order ? lhs.id.uuidString < rhs.id.uuidString : lhs.order < rhs.order
	}
}
