import GRDB

public extension FTS5TokenizerDescriptor {
	static func trigram(caseSensitive: Bool = false, removeDiacritics: Bool = false) -> FTS5TokenizerDescriptor {
		FTS5TokenizerDescriptor(components: [
			"trigram",
			"case_sensitive", caseSensitive ? "1" : "0",
			"remove_diacritics", removeDiacritics ? "1" : "0",
		])
	}
}
