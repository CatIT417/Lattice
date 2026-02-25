import SQLiteData

final class CreateBlocksTable: Migration {
	static func up(_ db: Database) throws {
		// All blocks (pages are blocks with a title)
		try db.create(table: "blocks") { table in
			table.id() // Internal entity ID (like Roam's e-id)

			table.column("string", .text) // Block text content (NULL for pages)
			table.column("title", .text) // Page title (NULL for regular blocks)
			table.column("dailyNoteDate", .text) // If this page is a daily note, the date in "YYYY-MM-DD" format

			// Hierarchy
			table.column("parentId", .integer).references("blocks", column: "id", onDelete: .cascade)
			table.column("pageId", .integer).indexed().references("blocks", column: "id", onDelete: .cascade) // Root page for this block
			table.column("order", .integer).notNull().defaults(to: 0) // Position among siblings

			// Display options
			table.column("heading", .integer) // 1, 2, or 3 (NULL = normal)
			table.column("viewType", .text).notNull().defaults(to: "bullet") // bullet', 'document', 'numbered'
			table.column("textAlign", .text).notNull().defaults(to: "left") // 'left', 'center', 'right', 'justify'
			table.column("isOpen", .boolean).notNull().defaults(to: true) // Collapsed state

			// Flexible properties (images, embeds, sliders, etc.)
			table.column("props", .jsonText) // JSON blob for extensible data

			// Timestamps
			table.column("createdAt", .datetime).notNull().defaults(sql: "(now())")
			table.column("updatedAt", .datetime).notNull().defaults(sql: "(now())").indexed()

			// Constraints
			table.constraint(#sql("CHECK (title IS NULL OR length(title) >= 3)")) // Enforce minimum title length for pages
			table.constraint(#sql("CHECK (title IS NOT NULL OR parentId IS NOT NULL)")) // Pages have title, blocks have parent
			table.constraint(#sql("CHECK (dailyNoteDate IS NULL OR title IS NOT NULL)")) // dailyNoteDate only on pages
			table.constraint(#sql("CHECK ((title IS NOT NULL) != (string IS NOT NULL))")) // XOR: either page OR block
		}

		// Indexes for common queries

		try db.create(indexOn: "blocks", columns: ["parentId", "order"])
		try db.create(indexOn: "blocks", columns: ["title"], condition: "title IS NOT NULL")
		try db.create(indexOn: "blocks", columns: ["dailyNoteDate"], condition: "dailyNoteDate IS NOT NULL")
	}

	static func down(_ db: Database) throws {
		try db.drop(table: "blocks")
	}
}
