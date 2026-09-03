import Foundation
import SQLiteData

struct TextRef {
	let target: String
	let kind: Reference.Kind
	let range: Range<String.Index>

	init(target: String, kind: Reference.Kind, range: Range<String.Index>) {
		self.kind = kind
		self.range = range
		self.target = target
	}

	init?(from span: InlineSpan) {
		guard let refKind = span.kind.asReferenceKind else { return nil }
		kind = refKind
		range = span.range
		target = span.content.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static let urlAllowed = tap(CharacterSet.urlPathAllowed) {
		$0.remove(charactersIn: "/")
	}

	var url: URL {
		switch kind {
			case .tag: URL(string: "lattice://tag/\(target.addingPercentEncoding(withAllowedCharacters: Self.urlAllowed)!)")!
			case .pageLink: URL(string: "lattice://page/\(target.addingPercentEncoding(withAllowedCharacters: Self.urlAllowed)!)")!
			case .blockRef, .blockEmbed: URL(string: "lattice://block/\(target.addingPercentEncoding(withAllowedCharacters: Self.urlAllowed)!)")!
		}
	}

	var prefix: String {
		switch kind {
			case .tag: "#"
			case .pageLink, .blockRef, .blockEmbed: ""
		}
	}

	func replacement(forRenamedPage title: String) -> String? {
		switch kind {
			case .pageLink: "[[\(title)]]"
			case .blockRef, .blockEmbed: nil
			case .tag: TagSyntax.makeTagReference(for: title)
		}
	}
}

extension String {
	func extractRefs() -> [TextRef] {
		guard contains("[") || contains("#") || contains("(") else { return [] }

		return InlineParser.referencesOnly
			.extractReferences(from: self)
			.compactMap { TextRef(from: $0) }
			.sorted { $0.range.lowerBound < $1.range.lowerBound }
	}
}

extension TextRef {
	struct Resolved {
		var targetID: UUID
		var kind: Reference.Kind
	}

	enum ResolvingError: Error {
		case unexpectedKind(Reference.Kind)
	}

	/// Resolves the reference to the id of the block it points at.
	///
	/// - Parameter createMissingPages: When true, `[[links]]` and `#tags` to pages that do not exist yet create the page.
	/// - Returns: `nil` when the target cannot be resolved without creating it, or when a `((block ref))` points at a block that does not exist.
	func resolved(using db: Database, createMissingPages: Bool) throws -> Resolved? {
		guard kind.isPage else {
			if !kind.isBlock { throw ResolvingError.unexpectedKind(kind) }

			guard let id = UUID(uuidString: target), let blockExists = try Select(Block.find(id).exists()).fetchOne(db), blockExists else {
				return nil
			}

			return Resolved(targetID: id, kind: kind)
		}

		if createMissingPages {
			return try Resolved(targetID: Page.findOrCreate(title: target, in: db).id, kind: kind)
		}

		let page = if let day = DayOfYear(title: target) { try Page.where { $0.dailyNoteDate.eq(day) }.fetchOne(db) }
		else { try Page.where { $0.title.eq(target) }.fetchOne(db) }

		return page.map { Resolved(targetID: $0.id, kind: kind) }
	}
}
