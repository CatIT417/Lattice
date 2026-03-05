import Foundation
import SQLiteData
import LinkPresentation

@Table("linkMetadata")
struct CachedLinkMetadata {
	@Column(primaryKey: true)
	var url: URL

	@Column(as: LPLinkMetadata.Archived.self)
	var metadata: LPLinkMetadata
}
