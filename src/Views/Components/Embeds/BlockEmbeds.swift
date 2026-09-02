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
		_metadataCache = FetchAll(
			CachedLinkMetadata.where { $0.url.in(embeds.map(\.url)) },
			animation: .default
		)
	}

	var body: some View {
		VStack {
			ForEach(metadataCache, id: \.url) { entry in
				LinkViewRepresentable(metadata: entry.metadata)
			}
		}
		.task(id: embeds) { await fetchMetadata() }
	}

	func fetchMetadata() async {
		let cacheMisses = embeds.filter { embed in
			!metadataCache.contains(where: { $0.url == embed.url })
		}

		await withTaskGroup { group in
			for embed in cacheMisses {
				group.addTask {
					await Result { try (embed.url, await LPMetadataProvider().fetchMetadata(for: embed.url)) }
				}
			}

			var entries: [CachedLinkMetadata] = []

			for await result in group {
				switch result {
					case let .failure(error): Logger.app.error("Failed to fetch embed metadata: \(error)", error: error)
					case let .success((url, metadata)): entries.append(CachedLinkMetadata(url: url, metadata: metadata))
				}
			}

			await withErrorReporting {
				try await database.write { db in
					try CachedLinkMetadata.upsert { entries }.execute(db)
				}
			}
		}
	}
}

#Preview {
	let _ = previewData()

	BlockEmbeds(embeds: [.tweet(url: URL(string: "https://x.com/steren/status/2029078589359178134?s=20")!)])
		.preview()
}
