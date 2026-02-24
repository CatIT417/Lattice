import Foundation

extension NSString {
	func hasPrefix(_ prefix: String, at location: Int) -> Bool {
		guard location >= 0 else { return false }
		let prefixLength = prefix.utf16.count
		guard location + prefixLength <= length else { return false }
		return substring(with: NSRange(location: location, length: prefixLength)) == prefix
	}

	func hasCharacter(_ character: Character, at location: Int) -> Bool {
		guard location >= 0, location < length else { return false }
		return substring(with: NSRange(location: location, length: 1)) == String(character)
	}
}
