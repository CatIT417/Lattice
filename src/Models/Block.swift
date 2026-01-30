import SQLiteData
import Foundation

@Table
struct Block: Identifiable, Equatable, Hashable, Sendable, HasChildren {
	enum ViewType: String, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case bullet, document, numbered
	}

	enum HeadingLevel: Int, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case h1 = 1, h2 = 2, h3 = 3
	}

	enum TextAlignment: String, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case left, center, right, justify
	}

	enum Kind: Equatable, Hashable, Sendable {
		case page(Page)
		case paragraph(Paragraph)
	}

	/// Internal entity ID (like Roam's e-id)
	let id: UUID

	/// Block text content (NULL for pages)
	var string: String?

	/// Page title (NULL for regular blocks)
	var title: String?

	/// If this page is a daily note, the date in "YYYY-MM-DD" format
	@Column(as: Date?.DayRepresentation.self)
	var dailyNoteDate: Date? = nil

	/// ID of parent block (NULL for root pages)
	var parentId: Block.ID?

	/// Root page for this block
	var pageId: Block.ID?

	/// Position among siblings
	var order: Int = 0

	/// 1, 2, or 3 (NULL = normal)
	var heading: HeadingLevel? = nil

	/// 'bullet', 'document', 'numbered'
	var viewType: ViewType = .bullet

	/// 'left', 'center', 'right', 'justify'
	var textAlign: TextAlignment = .left

	/// Collapsed state
	var isOpen: Bool = true

	/// JSON blob for extensible data
	var props: String? = nil

	var createdAt: Date = .now
	var updatedAt: Date = .now

	var kind: Kind {
		if let page = Page(block: self) { return .page(page) }
		if let paragraph = Paragraph(block: self) { return .paragraph(paragraph) }

		fatalError("Invalid Block: \(self)")
	}

	var destination: Destination.Pages {
		switch kind {
			case let .page(page): .page(id: page.id)
			case let .paragraph(paragraph): .block(id: paragraph.id)
		}
	}
}

extension Block.TableColumns {
	var isPage: some QueryExpression<Bool> {
		title.isNot(nil)
	}

	var isParagraph: some QueryExpression<Bool> {
		string.isNot(nil)
	}
}
