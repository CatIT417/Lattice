import SQLiteData
import Foundation

@Table
struct Block: Identifiable, Equatable, Hashable, Sendable {
	enum ViewType: String, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case bullet, document, numbered
	}

	enum HeadingLevel: Int, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case h1 = 1, h2 = 2, h3 = 3
	}

	enum TextAlignment: String, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case left, center, right, justify
	}

	/// Internal entity ID (like Roam's e-id)
	var id: UUID

	/// Block text content (NULL for pages)
	var string: String?

	/// Page title (NULL for regular blocks)
	var title: String?

	/// ID of parent block (NULL for root pages)
	var parentId: Block.ID?

	/// Root page for this block
	var pageId: Block.ID?

	/// Position among siblings
	var order: Int

	/// 1, 2, or 3 (NULL = normal)
	var heading: HeadingLevel?

	/// 'bullet', 'document', 'numbered'
	var viewType: ViewType

	/// 'left', 'center', 'right', 'justify'
	var textAlign: TextAlignment

	/// Collapsed state
	var isOpen: Bool

	/// JSON blob for extensible data
	var props: String?

	@Column(as: Date.UnixTimeRepresentation.self)
	var createdAt: Date

	@Column(as: Date.UnixTimeRepresentation.self)
	var updatedAt: Date
}
