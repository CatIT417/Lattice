import SwiftUI
import SQLiteData
import LinkPresentation
import ConcurrencyExtras

struct BlockEmbeds: View {
	let embeds: Set<EmbedInfo>

	@Dependency(\.defaultDatabase) private var database
	@FetchAll(CachedLinkMetadata.none) private var metadataCache

	init(embeds: Set<EmbedInfo>) {
		self.embeds = embeds
		let linkPreviewURLs = embeds.compactMap(\.linkPreviewURL)
		_metadataCache = FetchAll(
			CachedLinkMetadata.where { $0.url.in(linkPreviewURLs) },
			animation: .default
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			ForEach(embeds.sortedByURL) { embed in
				switch embed {
					case let .tweet(url):
						if let id = Tweet.id(from: url) {
							TweetView(id: id)
						} else {
							TweetUnavailableView(message: "This tweet URL could not be embedded.")
						}

					case let .youtube(url):
						if let entry = metadataCache.first(where: { $0.url == url }) {
							LinkViewRepresentable(metadata: entry.metadata)
						}
				}
			}
		}
		.task(id: embeds) { await fetchMetadata() }
	}

	func fetchMetadata() async {
		let cacheMisses = embeds.filter { embed in
			guard embed.linkPreviewURL != nil else { return false }
			return !metadataCache.contains(where: { $0.url == embed.url })
		}

		await withTaskGroup { group in
			for embed in cacheMisses {
				group.addTask {
					await Result { try (embed.url, await LPMetadataProvider().startFetchingMetadata(for: embed.url)) }
				}
			}

			var entries: [CachedLinkMetadata] = []

			for await result in group {
				switch result {
					case let .failure(error): Logger.app.error("Failed to fetch embed metadata: \(error)", error: error)
					case let .success((url, metadata)): entries.append(CachedLinkMetadata(url: url, metadata: metadata))
				}
			}

			withErrorReporting {
				try database.write { db in
					try CachedLinkMetadata.upsert { entries }.execute(db)
				}
			}
		}
	}
}

private extension EmbedInfo {
	var linkPreviewURL: URL? {
		switch self {
			case .tweet: nil
			case let .youtube(url): url
		}
	}
}

private extension Set where Element == EmbedInfo {
	var sortedByURL: [EmbedInfo] {
		sorted { $0.url.absoluteString < $1.url.absoluteString }
	}
}

#Preview {
	let _ = previewData()

	BlockEmbeds(embeds: [.tweet(url: URL(string: "https://x.com/steren/status/2029078589359178134?s=20")!)])
		.preview()
}
