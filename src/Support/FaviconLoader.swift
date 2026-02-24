import Nuke
import Foundation

enum FaviconLoader {
	/// Pipeline that accepts 404 responses (Google returns 404 with a fallback globe image).
	private static let pipeline = ImagePipeline(configuration: ImagePipeline.Configuration(dataLoader: DataLoader { response in
		guard let http = response as? HTTPURLResponse else { return nil }
		if (200..<300).contains(http.statusCode) || http.statusCode == 404 { return nil }
		return DataLoader.Error.statusCodeUnacceptable(http.statusCode)
	}))

	/// Synchronously check cache for a favicon image for the given URL.
	///
	/// - Returns: `nil` if the URL is not http(s), has no host, or isn't cached yet.
	static func image(for url: URL) -> PlatformImage? {
		guard let faviconURL = faviconURL(for: url) else { return nil }
		return pipeline.cache[ImageRequest(url: faviconURL)]?.image
	}

	/// The canonical favicon URL for a given external link, or `nil` if not applicable.
	/// Multiple link URLs on the same host share a single favicon URL.
	static func faviconURL(for url: URL) -> URL? {
		guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host else { return nil }
		return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
	}

	/// Ensure a favicon is loaded into cache.
	///
	/// - Parameter faviconURL: A favicon URL returned by ``faviconURL(for:)``.
	/// - Parameter onSuccess: Called on the main thread after a successful load.
	/// - Parameter onFailure: Called on the main thread if the load fails.
	static func ensureLoaded(faviconURL: URL, onSuccess: @escaping @MainActor () -> Void, onFailure: @escaping @MainActor () -> Void = {}) {
		let request = ImageRequest(url: faviconURL)

		// Already cached — still fire callback so this text view re-renders
		if pipeline.cache[request] != nil {
			DispatchQueue.main.async { onSuccess() }
			return
		}

		pipeline.loadImage(with: request) { result in
			switch result {
				case .success: DispatchQueue.main.async { onSuccess() }
				case .failure: DispatchQueue.main.async { onFailure() }
			}
		}
	}
}
