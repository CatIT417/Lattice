import SQLiteData
import Foundation

/// Links between blocks (the [[wiki links]] and ((block refs)))
@Table("blockReferences")
struct Reference: Equatable, Hashable, Sendable {
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

		func bracketOffset(for text: String) -> Int {
			switch self {
				case .pageLink, .blockRef, .blockEmbed: 2
				case .tag: text.starts(with: "#[[") ? 3 : 1
			}
		}
	}

	let sourceBlockId: Block.ID
	let kind: Kind
	let targetKey: String

	init?(sourceBlockId: Block.ID, reference: TextRef) {
		self.sourceBlockId = sourceBlockId
		kind = reference.kind
		if kind.isBlock {
			guard let id = UUID(uuidString: reference.target) else { return nil }
			targetKey = id.uuidString
		} else {
			targetKey = reference.target
		}
	}
}
