import Foundation

extension Page {
	enum TitleError: Error, LocalizedError {
		case tooShort, containsBrackets, existing, reserved, isDateTitle

		var errorDescription: String? {
			switch self {
				case .tooShort: "Page titles must have at least 3 characters."
				case .containsBrackets: "Page titles cannot contain [ or ]."
				case .existing: "A page with that title already exists."
				case .reserved: "That title is reserved for special pages."
				case .isDateTitle: "Titles that look like dates are reserved for daily notes."
			}
		}
	}

	static func validateTitle(_ title: String) throws(TitleError) {
		let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard title.count >= 3 else { throw .tooShort }
		guard !title.unicodeScalars.contains(where: { $0 == "[" || $0 == "]" }) else { throw .containsBrackets }
	}
}
