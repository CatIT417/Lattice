import SQLiteData
import Foundation

@Table
struct Paragraph: Identifiable, Equatable, Hashable, Codable, Sendable, HasChildren {
	/// Internal entity ID (like Roam's e-id)
	let id: UUID

	/// Block text content
	var string: String

	/// ID of parent block
	var parentId: Block.ID

	/// Root page for this block
	var pageId: Page.ID

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

	@Column(as: Date.UnixTimeRepresentation.self)
	var createdAt: Date = .now

	@Column(as: Date.UnixTimeRepresentation.self)
	var updatedAt: Date = .now

	var parentIsPage: Bool {
		parentId == pageId
	}

	init(id: UUID = UUID(), string: String, parentId: Block.ID, pageId: Page.ID, order: Int, heading: Block.HeadingLevel? = nil, viewType: Block.ViewType = .bullet, textAlign: Block.TextAlignment = .left, isOpen: Bool = true, props: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
		self.id = id
		self.props = props
		self.order = order
		self.string = string
		self.isOpen = isOpen
		self.pageId = pageId
		self.heading = heading
		self.viewType = viewType
		self.parentId = parentId
		self.textAlign = textAlign
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}

	init?(block: Block) {
		guard let string = block.string, let parentId = block.parentId, let pageId = block.pageId else {
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

enum ParagraphAlias: AliasName {}
