import Foundation
import LinkPresentation

extension LPMetadataProvider {
	func fetchMetadata(for url: URL) async throws -> LPLinkMetadata {
		nonisolated(unsafe) let provider = self

		return try await withTaskCancellationHandler {
			try await provider.startFetchingMetadata(for: url)
		} onCancel: {
			provider.cancel()
		}
	}
}
