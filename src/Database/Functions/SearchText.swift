import Foundation
import SQLiteData

@DatabaseFunction
nonisolated func searchDisplayTitle(_ title: String?) -> String? {
	title.map { Page.title(for: $0) }
}

@DatabaseFunction
nonisolated func searchDisplayString(_ string: String?) -> String? {
	string.map { renderPlainText(fromMarkup: $0) }
}

@DatabaseFunction
nonisolated func searchContains(_ text: String?, _ term: String) -> Bool {
	text?.range(of: term, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) != nil
}
