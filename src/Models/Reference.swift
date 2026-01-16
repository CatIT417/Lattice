import SQLiteData
import Foundation

/// Links between blocks (the [[wiki links]] and ((block refs)))
@Table("blockReferences")
struct Reference: Identifiable, Equatable, Hashable, Sendable {
	enum Kind: String, Equatable, Hashable, Sendable, QueryBindable {
		case tag
		case pageLink = "page_link"
		case blockRef = "block_ref"
		case blockEmbed = "block_embed"
	}

	var id: UUID
	var sourceBlockId: Block.ID
	var targetBlockId: Block.ID
	var kind: Kind

	@Column(as: Date.UnixTimeRepresentation.self)
	var createdAt: Date
}
