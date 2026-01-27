import Foundation
import SQLiteData

fileprivate let pagePattern = /\[\[([^\]]+)\]\]/
fileprivate let tagPattern = /#(?:\[\[([^\]]+)\]\]|(\w+))/
fileprivate let blockPattern = /\(\(([a-zA-Z0-9_-]{9})\)\)/

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
}

extension String {
	func extractRefs() -> [TextRef] {
		var refs: [TextRef] = []

		// [[Page Links]]
		for match in matches(of: pagePattern) where !String(match.1).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			refs.append(TextRef(target: String(match.1), kind: .pageLink, range: match.range))
		}

		// ((block refs))
		for match in matches(of: blockPattern) where UUID(uuidString: String(match.1)) != nil {
			refs.append(TextRef(target: String(match.1), kind: .blockRef, range: match.range))
		}

		// #tags and #[[Page Links]]
		for match in matches(of: tagPattern) where !String(match.1 ?? match.2!).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			refs.append(TextRef(target: String(match.1 ?? match.2!), kind: .tag, range: match.range))
		}

		return refs
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
