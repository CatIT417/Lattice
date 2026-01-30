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

		var isPage: Bool {
			switch self {
				case .pageLink, .tag: true
				case .blockRef, .blockEmbed: false
			}
		}

		var isBlock: Bool {
			switch self {
				case .pageLink, .tag: false
				case .blockRef, .blockEmbed: true
			}
		}
	}

	let id: UUID
	var sourceBlockId: Block.ID
	var targetBlockId: Block.ID
	var kind: Kind

	var createdAt: Date = .now
}
