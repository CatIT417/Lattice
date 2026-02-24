import SQLiteData
import Foundation
import CoreTransferable
import UniformTypeIdentifiers

@Table
struct Page: Identifiable, Equatable, Hashable, Sendable, HasChildren {
	/// Internal entity ID (like Roam's e-id)
	let id: UUID

	/// Page title (NULL for regular blocks)
	var title: String

	/// If this page is a daily note, the date in "YYYY-MM-DD" format
	var dailyNoteDate: DayOfYear?

	/// JSON blob for extensible data
	var props: String?

	var createdAt: Date
	var updatedAt: Date

	var isDailyNote: Bool {
		dailyNoteDate != nil
	}

	init(id: UUID? = nil, title: String, dailyNoteDate: DayOfYear? = nil, props: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
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

// MARK: - Daily Notes

extension Page {
	static func newDailyNote(for day: DayOfYear) -> Page {
		return Page(title: day.title(), dailyNoteDate: day)
	}

	static func createDailyNote(for day: DayOfYear, in db: Database) throws -> Page {
		let page = newDailyNote(for: day)

		let newlyCreatedBlock = try #sql("""
		INSERT INTO \(Block.self) (title, dailyNoteDate)
		SELECT \(bind: page.title), \(bind: page.dailyNoteDate!)
		WHERE NOT EXISTS (
		 SELECT 1 FROM \(Block.self)
		 WHERE \(Block.dailyNoteDate) = \(bind: page.dailyNoteDate!)
		)
		RETURNING *;
		""", as: Block.self).fetchOne(db)

		if let newlyCreatedBlock, let page = Page(block: newlyCreatedBlock) { return page }
		return try Page.where { $0.dailyNoteDate.eq(#bind(page.dailyNoteDate)) }.fetchOne(db)!
	}
}

// MARK: - Query Helpers

extension Page {
	static func findOrCreate(title: String, in db: Database) throws -> Page {
		let newlyCreatedBlock = try #sql("""
		INSERT INTO \(Block.self) (title)
		SELECT \(bind: title)
		WHERE NOT EXISTS (
			SELECT 1 FROM \(Block.self)
			WHERE \(Block.title) = \(bind: title)
		)
		RETURNING *;
		""", as: Block.self).fetchOne(db)

		if let newlyCreatedBlock, let page = Page(block: newlyCreatedBlock) { return page }
		return try Page.where { $0.title.eq(title) }.fetchOne(db)!
	}
}

// MARK: - Transferrable

extension Page: Transferable {
	static var transferRepresentation: some TransferRepresentation {
		ProxyRepresentation { page in
			try MarkdownExporter.exportPage(id: page.id)
		}

		FileRepresentation(exportedContentType: .text) { page in
			let markdown = try MarkdownExporter.exportPage(id: page.id)
			let url = URL.temporaryDirectory.appending(path: "\(page.title).md")

			try markdown.write(to: url, atomically: true, encoding: .utf8)

			return .init(url)
		}
	}
}
