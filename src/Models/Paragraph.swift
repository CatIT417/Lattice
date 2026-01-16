import SQLiteData
import Foundation

@Table
struct Paragraph: Identifiable, Equatable, Hashable, Codable, Sendable {
	/// Internal entity ID (like Roam's e-id)
	var id: UUID

	/// Block text content
	var string: String

	/// ID of parent block
	var parentId: Block.ID

	/// Root page for this block
	var pageId: Page.ID

	/// Position among siblings
	var order: Int

	/// 1, 2, or 3 (NULL = normal)
	var heading: Block.HeadingLevel?

	/// 'bullet', 'document', 'numbered'
	var viewType: Block.ViewType

	/// 'left', 'center', 'right', 'justify'
	var textAlign: Block.TextAlignment

	/// Collapsed state
	var isOpen: Bool

	/// JSON blob for extensible data
	var props: String?

	@Column(as: Date.UnixTimeRepresentation.self)
	var createdAt: Date

	@Column(as: Date.UnixTimeRepresentation.self)
	var updatedAt: Date
}
