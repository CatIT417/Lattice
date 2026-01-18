import Foundation

fileprivate let pagePattern = /\[\[([^\]]+)\]\]/
fileprivate let tagPattern = /#(?:\[\[([^\]]+)\]\]|(\w+))/
fileprivate let blockPattern = /\(\(([a-zA-Z0-9_-]{9})\)\)/

struct TextRef {
	let target: String
	let kind: Reference.Kind
	let range: Range<String.Index>

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
		for match in matches(of: pagePattern) {
			refs.append(TextRef(target: String(match.1), kind: .pageLink, range: match.range))
		}

		// ((block refs))
		for match in matches(of: blockPattern) {
			refs.append(TextRef(target: String(match.1), kind: .blockRef, range: match.range))
		}

		// #tags and #[[Page Links]]
		for match in matches(of: tagPattern) {
			refs.append(TextRef(target: String(match.1 ?? match.2!), kind: .tag, range: match.range))
		}

		return refs
	}
}
