import Foundation

extension String {
	var utf16Length: Int {
		utf16.count
	}

	func utf16Index(at offset: Int) -> String.Index? {
		guard offset >= 0, offset <= utf16Length else { return nil }
		return String.Index(utf16Offset: offset, in: self)
	}

	func character(atUTF16Offset offset: Int) -> Character? {
		guard let index = utf16Index(at: offset), index < endIndex else { return nil }
		return self[index]
	}

	func character(beforeUTF16Offset offset: Int) -> Character? {
		guard let index = utf16Index(at: offset), index > startIndex else { return nil }
		return self[self.index(before: index)]
	}

	func unicodeScalar(atUTF16Offset offset: Int) -> UnicodeScalar? {
		character(atUTF16Offset: offset)?.unicodeScalars.first
	}
}
