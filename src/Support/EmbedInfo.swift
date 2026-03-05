import Foundation

/// Represents an embeddable resource detected in block text.
enum EmbedInfo: Equatable, Hashable {
	case tweet(url: URL)
	case youtube(url: URL)

	var url: URL {
		switch self {
			case let .tweet(url): url
			case let .youtube(url): url
		}
	}

	/// Determines if a URL corresponds to an embeddable resource, and if so, returns the appropriate `EmbedInfo`.
	init?(url: URL) {
		switch true {
			case Self.isTweet(url): self = .tweet(url: url)
			case Self.isYouTube(url): self = .youtube(url: url)
			default: return nil
		}
	}

	/// Extracts all embeddable resources from a block's raw text.
	static func extract(from text: String) -> Set<EmbedInfo> {
		guard fastPathFilters.contains(where: { text.localizedCaseInsensitiveContains($0) }) else { return [] }

		return tap(Set<EmbedInfo>()) { collectEmbeds(from: InlineParser.default.parse(text), into: &$0) }
	}
}

extension EmbedInfo: Identifiable {
	var id: URL {
		url
	}
}

extension EmbedInfo {
	/// A list of substrings to check for before doing the more expensive embed extraction.
	fileprivate static let fastPathFilters = [
		"twitter.com/", "x.com/",
		"youtube.com/", "youtu.be/",
	]

	/// Recursively walks spans to find embeddable URLs.
	private static func collectEmbeds(from spans: [InlineSpan], into results: inout Set<EmbedInfo>) {
		for span in spans {
			if case let .link(_, embed) = span.kind {
				if let embed { results.insert(embed) }
			} else if !span.children.isEmpty {
				collectEmbeds(from: span.children, into: &results)
			}
		}
	}

	/// Determines if a URL is a tweet URL.
	private static func isTweet(_ url: URL) -> Bool {
		guard let host = url.host?.lowercased(), ["twitter.com", "x.com"].contains(where: {
			host == $0 || host.hasSuffix(".\($0)")
		}) else { return false }

		// ["/", "username", "status", "1234567890"]
		let components = url.pathComponents
		return components.count >= 4 && components[2] == "status" && Int64(components[3]) != nil
	}

	/// Determines if a URL is a YouTube video URL.
	private static func isYouTube(_ url: URL) -> Bool {
		guard let host = url.host?.lowercased() else { return false }

		if host == "youtube.com" || host.hasSuffix(".youtube.com") {
			// /watch?v=ID
			if url.pathComponents.count >= 2, url.pathComponents[1] == "watch",
			   let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value,
			   !v.isEmpty
			{ return true }

			// /embed/ID, /v/ID, /shorts/ID
			if url.pathComponents.count >= 3, ["embed", "v", "shorts"].contains(url.pathComponents[1]), !url.pathComponents[2].isEmpty {
				return true
			}

			return false
		}

		// youtu.be/ID
		if host == "youtu.be" || host.hasSuffix(".youtu.be") {
			return url.pathComponents.count >= 2 && !url.pathComponents[1].isEmpty
		}

		return false
	}
}
