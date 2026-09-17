import Foundation
import SQLiteData

@Table
struct BlockText: FTS5, Equatable {
	@Column(primaryKey: true)
	let rowid: Int
	let blockID: Block.ID
	@Column("title")
	let canonicalTitle: String?
	let string: String?
	let displayTitle: String?
	let displayString: String?
}

@Table("blockSearchIDs")
struct BlockSearchID: Equatable {
	let id: Int
	let blockID: Block.ID
}

// MARK: - Querying

extension BlockText {
	static func matching(_ text: String, titlesOnly: Bool = false) -> SelectOf<BlockText> {
		let query = SearchQuery(text)

		return Self
			.where { _ in !query.isEmpty }
			.where { texts in
				if let pattern = query.pattern {
					texts.match(titlesOnly ? "{title displayTitle} : (\(pattern))" : pattern)
				}
			}
			.where { texts in
				for term in query.shortTerms {
					if titlesOnly {
						$searchContains(texts.canonicalTitle, #bind(term)) || $searchContains(texts.displayTitle, #bind(term))
					} else {
						$searchContains(texts.canonicalTitle, #bind(term)) || $searchContains(texts.displayTitle, #bind(term))
							|| $searchContains(texts.string, #bind(term)) || $searchContains(texts.displayString, #bind(term))
					}
				}
			}
			.order {
				if query.pattern != nil {
					$0.bm25([\.canonicalTitle: 2, \.displayTitle: 3, \.displayString: 2])
				}
			}
			.order(by: \.blockID)
	}

	private struct SearchQuery {
		let isEmpty: Bool
		let pattern: String?
		let shortTerms: [String]

		init(_ text: String) {
			let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
			let terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
			let indexedTerms = terms.filter { $0.unicodeScalars.count >= 3 }

			isEmpty = terms.isEmpty
			shortTerms = terms.filter { $0.unicodeScalars.count < 3 }
			pattern = indexedTerms.isEmpty ? nil : "(\(indexedTerms.map(Self.quote).joined(separator: " AND "))) OR \(Self.quote(text))"
		}

		private static func quote(_ text: String) -> String {
			"\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
		}
	}
}
