import Foundation

fileprivate let pagePattern = /\[\[([^\]]+)\]\]/
fileprivate let tagPattern = /#(?:\[\[([^\]]+)\]\]|(\w+))/
fileprivate let blockPattern = /\(\(([a-zA-Z0-9_-]{9})\)\)/

extension String {
	func extractRefs() -> [(kind: Reference.Kind, target: String)] {
		var refs: [(Reference.Kind, String)] = []

		// [[Page Links]]
		for match in matches(of: pagePattern) {
			refs.append((.pageLink, String(match.1)))
		}

		// ((block refs))
		for match in matches(of: blockPattern) {
			refs.append((.blockRef, String(match.1)))
		}

		// #tags and #[[Page Links]]
		for match in matches(of: tagPattern) {
			refs.append((.tag, String((match.1 ?? match.2)!)))
		}

		return refs
	}
}
