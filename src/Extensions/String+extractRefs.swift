import Foundation
import SQLiteData

fileprivate nonisolated(unsafe) let pagePattern = /\[\[([^\]]+)\]\]/
fileprivate nonisolated(unsafe) let tagPattern = /#(?:\[\[([^\]]+)\]\]|(\w+))/
fileprivate nonisolated(unsafe) let blockPattern = /\(\(([a-fA-F0-9-]{36})\)\)/

struct TextRef {
	let target: String
	let kind: Reference.Kind
	let range: Range<String.Index>

	fileprivate init(target: String, kind: Reference.Kind, range: Range<String.Index>) {
		self.kind = kind
		self.range = range
		self.target = target
	}

	var url: URL {
		switch kind {
			case .tag: URL(string: "lattice://tag/\(target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
			case .pageLink: URL(string: "lattice://page/\(target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
			case .blockRef, .blockEmbed: URL(string: "lattice://block/\(target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
		}
	}

	func replacement(forRenamedPage title: String) -> String? {
		switch kind {
			case .pageLink: return "[[\(title)]]"
			case .blockRef, .blockEmbed: return nil
			case .tag:
				let needsBracketing = title.unicodeScalars.contains { scalar in
					!scalar.isASCII || CharacterSet.whitespacesAndNewlines.contains(scalar)
				}

				return needsBracketing ? "#[[\(title)]]" : "#\(title)"
		}
	}
}

extension String {
	func extractRefs() -> [TextRef] {
		var references: [TextRef] = []

		for match in matches(of: tagPattern) where !String(match.1 ?? match.2!).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			references.append(TextRef(target: String(match.1 ?? match.2!), kind: .tag, range: match.range))
		}

		for match in matches(of: pagePattern) where !String(match.1).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			guard !references.contains(where: { $0.range.contains(match.range) }) else { continue }
			references.append(TextRef(target: String(match.1), kind: .pageLink, range: match.range))
		}

		for match in matches(of: blockPattern) where UUID(uuidString: String(match.1)) != nil {
			references.append(TextRef(target: String(match.1), kind: .blockRef, range: match.range))
		}

		return references.sorted { $0.range.lowerBound < $1.range.lowerBound }
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

		let page = try Page.findOrCreate(title: target, in: db)
		return Resolved(targetID: page.id, kind: kind)
	}
}
