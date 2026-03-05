import Testing
import CustomDump
import Foundation

@testable import LatticeDev

extension Tests {
	@Suite("Support/EmbedInfo")
	struct EmbedInfoTest {}
}

// MARK: - init?(url:)

extension Tests.EmbedInfoTest {
	@Test("detects tweet URLs", arguments: [
		"https://twitter.com/user/status/123456",
		"https://x.com/elonmusk/status/9876543210",
		"https://mobile.twitter.com/user/status/123",
	])
	func detectsTweet(urlString: String) {
		let url = URL(string: urlString)!
		expectNoDifference(EmbedInfo(url: url), .tweet(url: url))
	}

	@Test("detects YouTube URLs", arguments: [
		"https://www.youtube.com/watch?v=dQw4w9WgXcQ",
		"https://youtube.com/embed/dQw4w9WgXcQ",
		"https://youtube.com/v/dQw4w9WgXcQ",
		"https://youtube.com/shorts/dQw4w9WgXcQ",
		"https://youtu.be/dQw4w9WgXcQ",
	])
	func detectsYouTube(urlString: String) {
		let url = URL(string: urlString)!
		expectNoDifference(EmbedInfo(url: url), .youtube(url: url))
	}

	@Test("rejects non-embeddable URLs", arguments: [
		// Twitter/X without valid status
		"https://twitter.com",
		"https://twitter.com/user",
		"https://twitter.com/user/status/abc",
		"https://twitter.com/user/status",
		// YouTube without valid video
		"https://youtube.com",
		"https://youtube.com/@channel",
		"https://youtube.com/watch?list=PLabc",
		"https://youtube.com/watch?v=",
		"https://youtu.be/",
		// Unrelated domains
		"https://example.com",
		"https://nottwitter.com/user/status/123",
	])
	func rejectsNonEmbeddable(urlString: String) {
		#expect(EmbedInfo(url: URL(string: urlString)!) == nil)
	}
}

// MARK: - extract(from:)

extension Tests.EmbedInfoTest {
	@Test("extracts tweet from text")
	func extractTweet() {
		let url = URL(string: "https://x.com/user/status/123")!
		expectNoDifference(EmbedInfo.extract(from: "Check this https://x.com/user/status/123"), [.tweet(url: url)])
	}

	@Test("extracts YouTube from text")
	func extractYouTube() {
		let url = URL(string: "https://youtu.be/abc123")!
		expectNoDifference(EmbedInfo.extract(from: "Watch https://youtu.be/abc123"), [.youtube(url: url)])
	}

	@Test("extracts multiple embeds")
	func extractMultiple() {
		let result = EmbedInfo.extract(from: "Tweet https://x.com/user/status/123 and video https://youtu.be/abc")
		expectNoDifference(result, [
			.tweet(url: URL(string: "https://x.com/user/status/123")!),
			.youtube(url: URL(string: "https://youtu.be/abc")!),
		])
	}

	@Test("returns empty when no embeds present", arguments: [
		"Just some plain text",
		"Visit https://example.com",
		"No embed keywords here https://example.com",
	])
	func extractEmpty(text: String) {
		expectNoDifference(EmbedInfo.extract(from: text), [])
	}

	@Test("deduplicates identical URLs")
	func extractDeduplicates() {
		let result = EmbedInfo.extract(from: "Same link twice: https://x.com/u/status/1 and https://x.com/u/status/1")
		#expect(result.count == 1)
	}
}
