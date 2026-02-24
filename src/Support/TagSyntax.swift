import Foundation

enum TagSyntax {
	static let simpleAllowedScalars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

	static func isSimpleTag(_ title: String) -> Bool {
		guard !title.isEmpty else { return false }
		return title.unicodeScalars.allSatisfy { simpleAllowedScalars.contains($0) }
	}

	static func makeTagReference(for title: String) -> String {
		isSimpleTag(title) ? "#\(title)" : "#[[\(title)]]"
	}
}
