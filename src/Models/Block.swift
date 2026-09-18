import Foundation
import SQLiteData

@Table
struct Block: Identifiable, Equatable, Hashable, Sendable, HasChildren {
	enum ViewType: String, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case bullet, document, numbered
	}

	enum HeadingLevel: Int, CaseIterable, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case h1 = 1, h2 = 2, h3 = 3
	}

	enum TextAlignment: String, CaseIterable, Equatable, Hashable, Codable, Sendable, QueryBindable {
		case left, center, right, justify

		var icon: String {
			switch self {
				case .left: "text.alignleft"
				case .justify: "text.justify"
				case .right: "text.alignright"
				case .center: "text.aligncenter"
			}
		}
	}

	/// Internal entity ID (like Roam's e-id)
	let id: UUID

	/// Block text content (NULL for pages)
	var string: String?

	/// Page title (NULL for regular blocks)
	var title: String?

	/// If this page is a daily note, the date in "YYYY-MM-DD" format
	var dailyNoteDate: DayOfYear?

	/// ID of parent block (NULL for root pages)
	var parentId: Block.ID?

	/// Position among siblings
	var order: Int = 0

	/// 1, 2, or 3 (NULL = normal)
	var heading: HeadingLevel?

	/// 'bullet', 'document', 'numbered'
	var viewType: ViewType = .bullet

	/// 'left', 'center', 'right', 'justify'
	var textAlign: TextAlignment = .left

	/// Collapsed state
	var isOpen: Bool = true

	/// JSON blob for extensible data
	var props: String?

	var createdAt: Date
	var updatedAt: Date

	var deletedAt: Date?
	var mergedInto: Block.ID?

	var destination: Destination.Pages {
		title == nil ? .paragraph(id: id) : .page(id: id)
	}

	init(id: UUID? = nil, string: String? = nil, title: String? = nil, dailyNoteDate: DayOfYear? = nil, parentId: Block.ID? = nil, order: Int = 0, heading: HeadingLevel? = nil, viewType: ViewType = .bullet, textAlign: TextAlignment = .left, isOpen: Bool = true, props: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil, mergedInto: Block.ID? = nil) {
		@Dependency(\.uuid) var uuid
		@Dependency(\.date.now) var now

		self.id = id ?? uuid()
		self.title = title
		self.props = props
		self.order = order
		self.isOpen = isOpen
		self.string = string
		self.heading = heading
		self.parentId = parentId
		self.viewType = viewType
		self.textAlign = textAlign
		self.createdAt = createdAt ?? now
		self.updatedAt = updatedAt ?? now
		self.dailyNoteDate = dailyNoteDate
		self.deletedAt = deletedAt
		self.mergedInto = mergedInto
	}
}

extension Block.TableColumns {
	var isVisible: some QueryExpression<Bool> {
		id.in(BlockHierarchy.where(\.isVisible).select(\.blockId))
	}

	var isPage: some QueryExpression<Bool> {
		title.isNot(nil)
	}

	var isParagraph: some QueryExpression<Bool> {
		string.isNot(nil)
	}

	/// The block itself and every descendant recorded in `blockAncestors`.
	func isInSubtree(rootedAt root: some QueryExpression<UUID>) -> some QueryExpression<Bool> {
		id.eq(root) || id.in(Ancestor.where { $0.ancestorId.eq(root) }.select(\.blockId))
	}
}
