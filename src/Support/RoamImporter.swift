import Foundation
import SQLiteData

struct RoamImporter {
	let roamPages: [RoamPage]

	init(url: URL) throws {
		let didAccess = url.startAccessingSecurityScopedResource()
		defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

		let data = try Data(contentsOf: url)
		roamPages = try JSONDecoder().decode([RoamPage].self, from: data)
	}

	/// Prepare all pages for import: validate, detect daily notes, build models
	func prepare() -> (valid: [PreparedPage], failed: [FailedPage]) {
		var failed = [FailedPage]()
		var valid = [PreparedPage]()
		var uidMapping = [String: UUID]()

		for roamPage in roamPages {
			guard roamPage.title.count >= 3 else {
				failed.append(FailedPage(title: roamPage.title, reason: .titleTooShort))
				continue
			}

			let updatedAt = roamPage.editTime.map { Date(millisecondsSince1970: $0) }
			let createdAt = roamPage.createTime.map { Date(millisecondsSince1970: $0) }

			var page = Page(title: roamPage.title, createdAt: createdAt, updatedAt: updatedAt)

			if let dailyDate = Self.parseDailyDate(uid: roamPage.uid, title: roamPage.title) {
				page = Page.newDailyNote(for: dailyDate, createdAt: createdAt, updatedAt: updatedAt)
			}

			var pageUIDs = [String: UUID]()

			valid.append(PreparedPage(
				page: page,
				paragraphs: Self.buildParagraphs(
					from: roamPage.children ?? [],
					parentId: page.id,
					pageId: page.id,
					uidMapping: &uidMapping,
					pageUIDs: &pageUIDs
				),
				blockUIDs: pageUIDs,
				roamTitle: page.title == roamPage.title ? nil : roamPage.title
			))
		}

		return (valid, failed)
	}

	/// Check which prepared pages conflict with existing pages in the database
	static func detectConflicts(in preparedPages: [PreparedPage]) -> [Int] {
		@Dependency(\.defaultDatabase) var database

		return withErrorReporting {
			try database.read { db in
				try preparedPages.enumerated().compactMap { i, prepared in
					if prepared.page.isSpecialPage { nil }
					else { try Self.findExistingPage(prepared).fetchCount(db) > 0 ? i : nil }
				}
			}
		} ?? []
	}

	/// Execute the import with resolved conflicts
	static func execute(pages: [PreparedPage]) throws -> Result {
		@Dependency(\.defaultDatabase) var database

		// Build UID mapping and title renames in a single pass.
		// UID mapping only includes non-skipped pages (we won't rewrite refs to skipped blocks).
		// Title renames include all pages (even skipped) since other imported pages may reference
		// the old title, and the canonical daily note already exists in the database.
		var uidMapping = [String: UUID]()
		var titleRenames = [String: String]()
		for prepared in pages {
			if prepared.resolution != .skip {
				uidMapping.merge(prepared.blockUIDs) { $1 }
			}
			if let roamTitle = prepared.roamTitle {
				titleRenames[roamTitle] = prepared.page.title
			}
		}

		var skipped = 0
		var imported = [ImportedPage]()

		try database.write { db in
			var resolvedPages = [(page: Page, prepared: PreparedPage)]()

			for prepared in pages {
				guard prepared.resolution != .skip else { skipped += 1; continue }

				let page = try findExistingPage(prepared).fetchOne(db) ?? createPage(prepared, in: db)
				resolvedPages.append((page, prepared))
			}

			for (page, prepared) in resolvedPages {
				if prepared.resolution == .replace {
					try Paragraph.where { $0.pageId.eq(page.id) }.delete().execute(db)
				}

				let orderOffset = try prepared.resolution == .merge
					? (Paragraph.where { $0.parentId.eq(page.id) }
						.select { $0.order.max() }
						.fetchOne(db)
						.flatMap { $0 } ?? -1) + 1
					: 0

				try Paragraph.insert {
					for paragraph in prepared.paragraphs {
						tap(paragraph) {
							$0.pageId = page.id
							$0.string = rewriteRefs(in: $0.string, uidMapping: uidMapping, titleRenames: titleRenames)

							if paragraph.parentIsPage {
								$0.parentId = page.id
								$0.order += orderOffset
							}
						}
					}
				}.execute(db)

				imported.append(ImportedPage(id: page.id, title: page.title))
			}
		}

		return Result(imported: imported, failed: [], skipped: skipped)
	}

	// MARK: - Private Helpers

	private static func findExistingPage(_ prepared: PreparedPage) throws -> Where<Page> {
		Page.where {
			if !prepared.page.isDailyNote { $0.title.eq(prepared.page.title) }
			else { $0.dailyNoteDate.eq(prepared.page.dailyNoteDate) }
		}
	}

	private static func createPage(_ prepared: PreparedPage, in db: Database) throws -> Page {
		if prepared.page.isDailyNote {
			try Page.createDailyNote(
				for: prepared.page.dailyNoteDate!,
				createdAt: prepared.page.createdAt,
				updatedAt: prepared.page.updatedAt,
				in: db
			)
		} else {
			try Page.findOrCreate(
				title: prepared.page.title,
				createdAt: prepared.page.createdAt,
				updatedAt: prepared.page.updatedAt,
				in: db
			)
		}
	}

	private static func id(for uid: String, in mapping: inout [String: UUID]) -> UUID {
		@Dependency(\.uuid) var uuid

		if let existing = mapping[uid] { return existing }
		return tap(uuid()) { mapping[uid] = $0 }
	}

	static func parseDailyDate(uid: String, title: String) -> DayOfYear? {
		// fast path: Roam daily pages UID is MM-DD-YYYY
		let parts = uid.split(separator: "-")
		if parts.count == 3, let month = Int(parts[0]), let day = Int(parts[1]), let year = Int(parts[2]) {
			let components = tap(DateComponents()) {
				$0.day = day
				$0.year = year
				$0.month = month
				$0.calendar = Calendar(identifier: .gregorian)
			}

			if components.isValidDate {
				return DayOfYear(day: day, month: month, year: year)
			}
		}

		return DayOfYear(title: title)
	}

	private static let roamBlockRefRegex = try! NSRegularExpression(pattern: #"\(\(([^)]+)\)\)"#)

	private static func rewriteRefs(in text: String, uidMapping: [String: UUID], titleRenames: [String: String]) -> String {
		var result = text

		for ref in text.extractRefs().reversed().filter({ $0.kind == .pageLink || $0.kind == .tag }) {
			if let newTitle = titleRenames[ref.target], let replacement = ref.replacement(forRenamedPage: newTitle) {
				result.replaceSubrange(ref.range, with: replacement)
			}
		}

		// Rewrite Roam block refs using regex (short UIDs don't match our parser)
		if !uidMapping.isEmpty {
			let matches = roamBlockRefRegex.matches(in: result, range: NSRange(location: 0, length: result.utf16Length))
			for match in matches.reversed() {
				guard let uidRange = Range(match.range(at: 1), in: result),
				      let fullRange = Range(match.range, in: result),
				      let uuid = uidMapping[String(result[uidRange])]
				else { continue }

				result.replaceSubrange(fullRange, with: "((\(uuid.uuidString)))")
			}
		}

		return result
	}

	private static func buildParagraphs(
		from blocks: [RoamBlock],
		parentId: Block.ID,
		pageId: Page.ID,
		uidMapping: inout [String: UUID],
		pageUIDs: inout [String: UUID]
	) -> [Paragraph] {
		var paragraphs = [Paragraph]()

		for (order, block) in blocks.enumerated() {
			let id = id(for: block.uid, in: &uidMapping)
			pageUIDs[block.uid] = id

			paragraphs.append(Paragraph(
				id: id,
				string: block.string,
				parentId: parentId,
				pageId: pageId,
				order: order,
				heading: block.heading.flatMap(Block.HeadingLevel.init(rawValue:)),
				textAlign: block.textAlign.flatMap(Block.TextAlignment.init(rawValue:)) ?? .left,
				createdAt: block.createTime.map { Date(millisecondsSince1970: $0) },
				updatedAt: block.editTime.map { Date(millisecondsSince1970: $0) }
			))

			if let children = block.children, !children.isEmpty {
				paragraphs.append(contentsOf: buildParagraphs(
					from: children,
					parentId: id,
					pageId: pageId,
					uidMapping: &uidMapping,
					pageUIDs: &pageUIDs
				))
			}
		}

		return paragraphs
	}
}

// MARK: - Roam JSON Models

extension RoamImporter {
	struct RoamPage: Decodable {
		let uid: String
		let title: String
		let children: [RoamBlock]?

		let editTime: Int?
		let createTime: Int?

		private enum CodingKeys: String, CodingKey {
			case uid, title, children
			case editTime = "edit-time"
			case createTime = "create-time"
		}
	}

	struct RoamBlock: Decodable {
		let uid: String
		let string: String
		let children: [RoamBlock]?
		let heading: Int?
		let textAlign: String?

		let createTime: Int?
		let editTime: Int?

		private enum CodingKeys: String, CodingKey {
			case uid, string, children, heading
			case editTime = "edit-time"
			case textAlign = "text-align"
			case createTime = "create-time"
		}
	}
}

// MARK: - Import Types

extension RoamImporter {
	struct PreparedPage {
		let page: Page
		let paragraphs: [Paragraph]
		/// Roam UID → Lattice UUID for blocks belonging to this page
		let blockUIDs: [String: UUID]
		/// Original Roam title when it differs from Lattice's canonical title (daily notes only)
		let roamTitle: String?
		var resolution: ConflictResolution = .merge
	}

	enum ConflictResolution {
		case merge, skip, replace
	}

	struct ImportedPage {
		let id: Page.ID
		let title: String
	}

	struct FailedPage {
		enum Reason: Error, LocalizedError {
			case titleTooShort

			var errorDescription: String? {
				switch self {
					case .titleTooShort: "Title must be at least 3 characters"
				}
			}
		}

		let title: String
		let reason: Reason
	}

	struct Result {
		let imported: [ImportedPage]
		let failed: [FailedPage]
		let skipped: Int
	}
}
