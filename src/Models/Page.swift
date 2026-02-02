import SQLiteData
import Foundation

@Table
struct Page: Identifiable, Equatable, Hashable, Sendable, HasChildren {
	/// Internal entity ID (like Roam's e-id)
	let id: UUID

	/// Page title (NULL for regular blocks)
	var title: String

	/// If this page is a daily note, the date in "YYYY-MM-DD" format
	@Column(as: Date?.DayRepresentation.self)
	var dailyNoteDate: Date?

	/// JSON blob for extensible data
	var props: String?

	var createdAt: Date
	var updatedAt: Date

	init(id: UUID? = nil, title: String, dailyNoteDate: Date? = nil, props: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
		@Dependency(\.uuid) var uuid
		@Dependency(\.date.now) var now

		self.id = id ?? uuid()
		self.title = title
		self.props = props
		self.createdAt = createdAt ?? now
		self.updatedAt = updatedAt ?? now
		self.dailyNoteDate = dailyNoteDate
	}

	init?(block: Block) {
		guard let title = block.title else { return nil }

		id = block.id
		self.title = title
		props = block.props
		createdAt = block.createdAt
		updatedAt = block.updatedAt
		dailyNoteDate = block.dailyNoteDate
	}
}

extension Page {
	static func createDailyNote(for date: Date) -> Page {
		let formatter = tap(DateFormatter()) { $0.dateFormat = "MMMM '<dth>', yyyy" }
		var pageTitle = formatter.string(from: date)
		if pageTitle.contains("<dth>") { pageTitle.replace("<dth>", with: date.ordinal) }

		return Page(title: pageTitle, dailyNoteDate: date)
	}
}

extension Page {
	static func findOrCreate(title: String, in db: Database) throws -> Page {
		try #sql("INSERT INTO \(Block.self) (title) SELECT \(bind: title) WHERE NOT EXISTS (SELECT 1 FROM \(Block.self) WHERE \(Block.title) = \(bind: title));").execute(db)

		return try Page.where { $0.title == title }.fetchOne(db)!
	}
}
