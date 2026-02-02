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

	var createdAt: Date

	init(id: UUID? = nil, sourceBlockId: Block.ID, targetBlockId: Block.ID, kind: Kind, createdAt: Date? = nil) {
		@Dependency(\.uuid) var uuid
		@Dependency(\.date.now) var now

		self.kind = kind
		self.id = id ?? uuid()
		self.sourceBlockId = sourceBlockId
		self.targetBlockId = targetBlockId
		self.createdAt = createdAt ?? now
	}
}
