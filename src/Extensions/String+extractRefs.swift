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
		target = span.content
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

	func resolved(using db: Database) throws -> Resolved {
		guard kind.isPage else {
			if !kind.isBlock { throw ResolvingError.unexpectedKind(kind) }
			return Resolved(targetID: UUID(uuidString: target)!, kind: kind)
		}

		let page = if let dayOfYear = DayOfYear(title: target) { try Page.createDailyNote(for: dayOfYear, in: db) }
		else { try Page.findOrCreate(title: target, in: db) }

		return Resolved(targetID: page.id, kind: kind)
	}
}
