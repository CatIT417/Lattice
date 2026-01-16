import SQLiteData
import Foundation

@Table
struct Page: Identifiable, Equatable, Hashable, Sendable {
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
}

extension Page {
	@Selection
	struct WithContent {
		let page: Page
		@Column(as: [Paragraph].JSONRepresentation.self)
		let content: [Paragraph]
	}

	static func withContent(id: ID) -> some Statement<WithContent> {
		Page
			.find(id)
			.group(by: \.id)
			.join(Ancestor.all) { $0.id.eq($1.ancestorId) }
			.join(Paragraph.all) { $1.blockId.eq($2.id) }
			.select { page, _, paragraph in
				WithContent.Columns(page: page, content: paragraph.jsonGroupArray())
			}
	}
}
