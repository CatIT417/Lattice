import SQLiteData
import Foundation

@Table
struct Page: Identifiable, Equatable, Hashable, Sendable, HasChildren {
	/// Internal entity ID (like Roam's e-id)
	var id: UUID

	/// Page title (NULL for regular blocks)
	var title: String

	/// JSON blob for extensible data
	var props: String?

	@Column(as: Date.UnixTimeRepresentation.self)
	var createdAt: Date

	@Column(as: Date.UnixTimeRepresentation.self)
	var updatedAt: Date

	init(id: UUID = UUID(), title: String, props: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
		self.id = id
		self.title = title
		self.props = props
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}

	init?(block: Block) {
		guard let title = block.title else { return nil }

		id = block.id
		self.title = title
		props = block.props
		createdAt = block.createdAt
		updatedAt = block.updatedAt
	}
}
