import Foundation

struct Tweet: Decodable, Equatable, Identifiable, Sendable {
	var id: String { idString }

	var idString: String
	var text: String
	var createdAt: Date
	var displayTextRange: TextRange
	var entities = Entities()
	var user: User
	var mediaDetails: [Media] = []
	var card: Card? = nil
	var quotedTweet: QuotedTweet? = nil
	var parent: ParentTweet? = nil
	var inReplyToScreenName: String? = nil
	var inReplyToStatusIDString: String? = nil
	var noteTweet: NoteTweet? = nil

	var url: URL {
		URL(string: "https://x.com/\(user.screenName)/status/\(idString)")!
	}

	var inReplyToURL: URL? {
		guard let screenName = inReplyToScreenName, let statusID = inReplyToStatusIDString else { return nil }
		return URL(string: "https://x.com/\(screenName)/status/\(statusID)")
	}

	static func load(_ id: String) async throws -> Tweet {
		guard isValidID(id) else { throw LoadError.invalidID(id) }

		var request = URLRequest(url: requestURL(for: id))
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let response = response as? HTTPURLResponse else { throw LoadError.invalidResponse }

		let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

		if response.statusCode == 404 {
			throw LoadError.notFound(id)
		}

		guard (200..<300).contains(response.statusCode) else {
			throw LoadError.httpStatus(response.statusCode, json?["error"] as? String)
		}

		if json?["__typename"] as? String == "TweetTombstone" {
			throw LoadError.tombstone(id)
		}

		if json?.isEmpty == true {
			throw LoadError.notFound(id)
		}

		return try decoder.decode(Tweet.self, from: data)
	}

	static func id(from url: URL) -> String? {
		let components = url.pathComponents
		guard components.count >= 4, components[2] == "status", isValidID(components[3]) else { return nil }
		return components[3]
	}

	static func textSegments(for tweet: some TweetTextProviding) -> [TextSegment] {
		let characters = tweet.text.unicodeScalars.map(String.init)
		guard let displayRange = tweet.displayTextRange.clamped(toCount: characters.count) else { return [] }

		let hiddenEntityStart = hiddenEntityStart(for: tweet, in: displayRange)
		let displayEnd = hiddenEntityStart
			.map { min(displayRange.end, max(displayRange.start, $0)) } ?? displayRange.end
		let renderRange = TextRange(start: displayRange.start, end: displayEnd)

		var rawEntities: [RawTextEntity] = []
		rawEntities += tweet.entities.hashtags.map {
			RawTextEntity(indices: $0.indices, displayText: nil, url: URL(string: "https://x.com/hashtag/\($0.text)"))
		}
		rawEntities += tweet.entities.userMentions.map {
			RawTextEntity(indices: $0.indices, displayText: nil, url: URL(string: "https://x.com/\($0.screenName)"))
		}
		rawEntities += tweet.entities.urls.map {
			RawTextEntity(indices: $0.indices, displayText: $0.displayURL, url: $0.expandedURL)
		}
		rawEntities += tweet.entities.symbols.map {
			RawTextEntity(indices: $0.indices, displayText: nil, url: URL(string: "https://x.com/search?q=%24\($0.text)"))
		}

		rawEntities.sort { lhs, rhs in
			if lhs.indices.start == rhs.indices.start {
				lhs.indices.end < rhs.indices.end
			} else {
				lhs.indices.start < rhs.indices.start
			}
		}

		var cursor = renderRange.start
		var segments: [TextSegment] = []

		for entity in rawEntities {
			guard entity.indices.start >= renderRange.start, entity.indices.start < renderRange.end else { continue }
			guard entity.indices.start >= cursor else { continue }

			if cursor < entity.indices.start {
				segments.append(TextSegment(text: characters[cursor..<entity.indices.start].joined(), url: nil))
			}

			let end = min(entity.indices.end, renderRange.end)
			if entity.indices.start < end {
				segments.append(TextSegment(
					text: entity.displayText ?? characters[entity.indices.start..<end].joined(),
					url: entity.url
				))
				cursor = end
			}
		}

		if cursor < renderRange.end {
			segments.append(TextSegment(text: characters[cursor..<renderRange.end].joined(), url: nil))
		}

		trimTrailingWhitespace(from: &segments)
		return segments
	}

	private static func hiddenEntityStart(for tweet: some TweetTextProviding, in displayRange: TextRange) -> Int? {
		var starts = tweet.entities.media.map(\.indices.start)

		if let quotedTweetID = tweet.quotedTweetID {
			starts += tweet.entities.urls.compactMap { entity in
				guard let url = entity.expandedURL ?? entity.url, id(from: url) == quotedTweetID else { return nil }
				return entity.indices.start
			}
		}

		if let cardURL = tweet.cardURL {
			starts += tweet.entities.urls.compactMap { entity in
				guard entity.indices.end >= displayRange.end else { return nil }
				guard entity.matches(cardURL: cardURL) else { return nil }
				return entity.indices.start
			}
		}

		return starts
			.filter { $0 >= displayRange.start && $0 <= displayRange.end }
			.min()
	}

	private static func trimTrailingWhitespace(from segments: inout [TextSegment]) {
		while let last = segments.last {
			guard last.url == nil else { return }

			let trimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
			if !trimmed.isEmpty {
				segments[segments.count - 1].text = trimmed
				return
			}

			segments.removeLast()
		}
	}

	private static let syndicationURL = URL(string: "https://cdn.syndication.twimg.com/tweet-result")!

	private static let features = [
		"tfw_timeline_list:",
		"tfw_follower_count_sunset:true",
		"tfw_tweet_edit_backend:on",
		"tfw_refsrc_session:on",
		"tfw_fosnr_soft_interventions_enabled:on",
		"tfw_show_birdwatch_pivots_enabled:on",
		"tfw_show_business_verified_badge:on",
		"tfw_duplicate_scribes_to_settings:on",
		"tfw_use_profile_image_shape_enabled:on",
		"tfw_show_blue_verified_badge:on",
		"tfw_legacy_timeline_sunset:true",
		"tfw_show_gov_verified_badge:on",
		"tfw_show_business_affiliate_badge:on",
		"tfw_tweet_edit_frontend:on",
	]

	private static var decoder: JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .custom { decoder in
			let container = try decoder.singleValueContainer()
			let string = try container.decode(String.self)

			let formatter = ISO8601DateFormatter()
			formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
			if let date = formatter.date(from: string) { return date }

			formatter.formatOptions = [.withInternetDateTime]
			if let date = formatter.date(from: string) { return date }

			throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
		}
		return decoder
	}

	private static func requestURL(for id: String) -> URL {
		var components = URLComponents(url: syndicationURL, resolvingAgainstBaseURL: false)!
		components.queryItems = [
			URLQueryItem(name: "id", value: id),
			URLQueryItem(name: "lang", value: "en"),
			URLQueryItem(name: "features", value: features.joined(separator: ";")),
			URLQueryItem(name: "token", value: token(for: id)),
		]
		return components.url!
	}

	private static func isValidID(_ id: String) -> Bool {
		!id.isEmpty && id.count <= 40 && id.allSatisfy(\.isNumber)
	}

	private static func token(for id: String) -> String {
		guard let number = Double(id) else { return "0" }
		let value = number / 1e15 * Double.pi
		return base36String(value).filter { $0 != "0" && $0 != "." }
	}

	private static func base36String(_ value: Double) -> String {
		let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
		guard value.isFinite, value >= 0 else { return "0" }

		let integerPart = value.rounded(.towardZero)
		guard integerPart <= Double(UInt64.max) else { return "0" }

		var integer = UInt64(integerPart)
		var integerString = ""
		repeat {
			integerString.insert(digits[Int(integer % 36)], at: integerString.startIndex)
			integer /= 36
		} while integer > 0

		var fraction = value - integerPart
		guard fraction > 0 else { return integerString }

		var fractionString = ""
		for _ in 0..<16 {
			fraction *= 36
			let digit = min(Int(fraction), 35)
			fractionString.append(digits[digit])
			fraction -= Double(digit)
			if fraction < 1e-12 { break }
		}

		return "\(integerString).\(fractionString)"
	}

	enum LoadError: Error, Equatable, LocalizedError {
		case invalidID(String)
		case invalidResponse
		case notFound(String)
		case tombstone(String)
		case httpStatus(Int, String?)

		var errorDescription: String? {
			switch self {
				case let .invalidID(id): "Invalid tweet id: \(id)"
				case .invalidResponse: "Twitter returned an invalid response."
				case let .notFound(id): "Tweet \(id) does not exist or has been deleted."
				case let .tombstone(id): "Tweet \(id) is no longer publicly available."
				case let .httpStatus(status, message): message ?? "Twitter returned HTTP \(status)."
			}
		}
	}

	struct User: Decodable, Equatable, Sendable {
		var name: String
		var screenName: String
		var profileImageURL: URL? = nil
		var profileImageShape: ProfileImageShape = .circle
		var verified = false
		var verifiedType: VerifiedType? = nil
		var isBlueVerified = false
		var highlightedLabel: HighlightedLabel? = nil

		var url: URL {
			URL(string: "https://x.com/\(screenName)")!
		}

		var highResolutionProfileImageURL: URL? {
			profileImageURL(size: "400x400") ?? profileImageURL
		}

		func profileImageURL(size: String) -> URL? {
			guard let profileImageURL, !profileImageURL.pathExtension.isEmpty else { return profileImageURL }

			let filename = profileImageURL.deletingPathExtension().lastPathComponent
			let baseName = ["_normal", "_bigger", "_mini", "_400x400"].reduce(filename) { name, suffix in
				name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
			}

			return profileImageURL
				.deletingLastPathComponent()
				.appendingPathComponent("\(baseName)_\(size)")
				.appendingPathExtension(profileImageURL.pathExtension)
		}

		enum CodingKeys: String, CodingKey {
			case name
			case screenName = "screen_name"
			case profileImageURL = "profile_image_url_https"
			case profileImageShape = "profile_image_shape"
			case verified
			case verifiedType = "verified_type"
			case isBlueVerified = "is_blue_verified"
			case highlightedLabel = "highlighted_label"
		}

		enum ProfileImageShape: String, Decodable, Equatable, Sendable {
			case circle = "Circle"
			case square = "Square"
			case hexagon = "Hexagon"
		}

		enum VerifiedType: String, Decodable, Equatable, Sendable {
			case business = "Business"
			case government = "Government"
		}

		struct HighlightedLabel: Decodable, Equatable, Sendable {
			var labelDescription: String?
			var badge: Badge?

			enum CodingKeys: String, CodingKey {
				case labelDescription = "description"
				case badge
			}

			struct Badge: Decodable, Equatable, Sendable {
				var url: URL?

				enum CodingKeys: String, CodingKey {
					case url
				}

				init(from decoder: Decoder) throws {
					let container = try decoder.container(keyedBy: CodingKeys.self)
					url = try container.decodeURLIfPresent(forKey: .url)
				}
			}
		}
	}

	struct QuotedTweet: Decodable, Equatable, Identifiable, Sendable, TweetTextProviding {
		var id: String { idString }

		var idString: String
		var text: String
		var displayTextRange: TextRange
		var entities: Entities
		var user: User
		var mediaDetails: [Media]
		var noteTweet: NoteTweet?
		var inReplyToScreenName: String?
		var inReplyToStatusIDString: String?

		var url: URL {
			URL(string: "https://x.com/\(user.screenName)/status/\(idString)")!
		}

		var inReplyToURL: URL? {
			guard let screenName = inReplyToScreenName, let statusID = inReplyToStatusIDString else { return nil }
			return URL(string: "https://x.com/\(screenName)/status/\(statusID)")
		}

		enum CodingKeys: String, CodingKey {
			case idString = "id_str"
			case text
			case displayTextRange = "display_text_range"
			case entities
			case user
			case mediaDetails
			case noteTweet = "note_tweet"
			case inReplyToScreenName = "in_reply_to_screen_name"
			case inReplyToStatusIDString = "in_reply_to_status_id_str"
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			idString = try container.decode(String.self, forKey: .idString)
			text = try container.decode(String.self, forKey: .text)
			displayTextRange = try container.decode(TextRange.self, forKey: .displayTextRange)
			entities = try container.decodeIfPresent(Entities.self, forKey: .entities) ?? Entities()
			user = try container.decode(User.self, forKey: .user)
			mediaDetails = try container.decodeIfPresent([Media].self, forKey: .mediaDetails) ?? []
			noteTweet = try container.decodeIfPresent(NoteTweet.self, forKey: .noteTweet)
			inReplyToScreenName = try container.decodeIfPresent(String.self, forKey: .inReplyToScreenName)
			inReplyToStatusIDString = try container.decodeIfPresent(String.self, forKey: .inReplyToStatusIDString)
		}
	}

	struct ParentTweet: Decodable, Equatable, Identifiable, Sendable, TweetTextProviding {
		var id: String { idString }

		var idString: String
		var text: String
		var createdAt: Date
		var displayTextRange: TextRange
		var entities: Entities
		var user: User
		var quotedTweet: QuotedTweet?
		var inReplyToScreenName: String?
		var inReplyToStatusIDString: String?
		var noteTweet: NoteTweet?

		var url: URL {
			URL(string: "https://x.com/\(user.screenName)/status/\(idString)")!
		}

		var inReplyToURL: URL? {
			guard let screenName = inReplyToScreenName, let statusID = inReplyToStatusIDString else { return nil }
			return URL(string: "https://x.com/\(screenName)/status/\(statusID)")
		}

		var quotedTweetID: String? {
			quotedTweet?.idString
		}

		enum CodingKeys: String, CodingKey {
			case idString = "id_str"
			case text
			case createdAt = "created_at"
			case displayTextRange = "display_text_range"
			case entities
			case user
			case quotedTweet = "quoted_tweet"
			case inReplyToScreenName = "in_reply_to_screen_name"
			case inReplyToStatusIDString = "in_reply_to_status_id_str"
			case noteTweet = "note_tweet"
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			idString = try container.decode(String.self, forKey: .idString)
			text = try container.decode(String.self, forKey: .text)
			createdAt = try container.decode(Date.self, forKey: .createdAt)
			displayTextRange = try container.decode(TextRange.self, forKey: .displayTextRange)
			entities = try container.decodeIfPresent(Entities.self, forKey: .entities) ?? Entities()
			user = try container.decode(User.self, forKey: .user)
			quotedTweet = try container.decodeIfPresent(QuotedTweet.self, forKey: .quotedTweet)
			inReplyToScreenName = try container.decodeIfPresent(String.self, forKey: .inReplyToScreenName)
			inReplyToStatusIDString = try container.decodeIfPresent(String.self, forKey: .inReplyToStatusIDString)
			noteTweet = try container.decodeIfPresent(NoteTweet.self, forKey: .noteTweet)
		}
	}

	struct TextRange: Decodable, Equatable, Sendable {
		var start: Int
		var end: Int

		func clamped(toCount count: Int) -> TextRange? {
			let lower = min(max(start, 0), count)
			let upper = min(max(end, lower), count)
			guard lower < upper else { return nil }
			return TextRange(start: lower, end: upper)
		}
	}

	struct TextSegment: Equatable, Sendable {
		var text: String
		var url: URL?
	}

	struct Entities: Decodable, Equatable, Sendable {
		var hashtags: [HashtagEntity] = []
		var urls: [URLEntity] = []
		var userMentions: [UserMentionEntity] = []
		var symbols: [SymbolEntity] = []
		var media: [MediaEntity] = []

		enum CodingKeys: String, CodingKey {
			case hashtags
			case urls
			case userMentions = "user_mentions"
			case symbols
			case media
		}

	}

	struct HashtagEntity: Decodable, Equatable, Sendable {
		var indices: TextRange
		var text: String
	}

	struct UserMentionEntity: Decodable, Equatable, Sendable {
		var indices: TextRange
		var screenName: String

		enum CodingKeys: String, CodingKey {
			case indices
			case screenName = "screen_name"
		}
	}

	struct URLEntity: Decodable, Equatable, Sendable {
		var displayURL: String
		var expandedURL: URL?
		var indices: TextRange
		var url: URL?

		enum CodingKeys: String, CodingKey {
			case displayURL = "display_url"
			case expandedURL = "expanded_url"
			case indices
			case url
		}

		func matches(cardURL: URL) -> Bool {
			[expandedURL, url]
				.compactMap(\.self)
				.contains { $0.isSameTweetCardURL(as: cardURL) }
		}
	}

	struct SymbolEntity: Decodable, Equatable, Sendable {
		var indices: TextRange
		var text: String
	}

	struct MediaEntity: Decodable, Equatable, Sendable {
		var indices: TextRange
	}

	struct Media: Decodable, Equatable, Identifiable, Sendable {
		var id: String {
			mediaURL?.absoluteString ?? displayURL
		}

		var kind: Kind
		var displayURL: String
		var mediaURL: URL?
		var originalInfo: OriginalInfo?
		var videoInfo: VideoInfo?

		var aspectRatio: Double {
			if let originalInfo, originalInfo.width > 0, originalInfo.height > 0 {
				return Double(originalInfo.width) / Double(originalInfo.height)
			}
			if let aspectRatio = videoInfo?.aspectRatio, aspectRatio.count == 2, aspectRatio[1] > 0 {
				return Double(aspectRatio[0]) / Double(aspectRatio[1])
			}
			return 16.0 / 9.0
		}

		var imageURL: URL? {
			imageURL(size: "small")
		}

		var originalImageURL: URL? {
			imageURL(size: "orig")
		}

		var playableVideoURL: URL? {
			videoInfo?.playableVideoURL
		}

		func imageURL(size: String) -> URL? {
			guard let mediaURL else { return nil }
			guard !mediaURL.pathExtension.isEmpty else { return mediaURL }

			var components = URLComponents(url: mediaURL.deletingPathExtension(), resolvingAgainstBaseURL: false)
			components?.queryItems = [
				URLQueryItem(name: "format", value: mediaURL.pathExtension),
				URLQueryItem(name: "name", value: size),
			]
			return components?.url ?? mediaURL
		}

		enum CodingKeys: String, CodingKey {
			case kind = "type"
			case displayURL = "display_url"
			case mediaURL = "media_url_https"
			case originalInfo = "original_info"
			case videoInfo = "video_info"
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .photo
			displayURL = try container.decodeIfPresent(String.self, forKey: .displayURL) ?? ""
			mediaURL = try container.decodeURLIfPresent(forKey: .mediaURL)
			originalInfo = try container.decodeIfPresent(OriginalInfo.self, forKey: .originalInfo)
			videoInfo = try container.decodeIfPresent(VideoInfo.self, forKey: .videoInfo)
		}

		enum Kind: String, Decodable, Equatable, Sendable {
			case photo
			case video
			case animatedGIF = "animated_gif"
		}
	}

	struct OriginalInfo: Decodable, Equatable, Sendable {
		var height: Int
		var width: Int
	}

	struct VideoInfo: Decodable, Equatable, Sendable {
		var aspectRatio: [Int]
		var variants: [Variant]

		var playableVideoURL: URL? {
			let mp4Variants = variants
				.filter { $0.contentType == "video/mp4" && $0.url != nil }
				.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }

			return mp4Variants.count > 1 ? mp4Variants[1].url : mp4Variants.first?.url
		}

		enum CodingKeys: String, CodingKey {
			case aspectRatio = "aspect_ratio"
			case variants
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			aspectRatio = try container.decodeIfPresent([Int].self, forKey: .aspectRatio) ?? []
			variants = try container.decodeIfPresent([Variant].self, forKey: .variants) ?? []
		}

		struct Variant: Decodable, Equatable, Sendable {
			var bitrate: Int?
			var contentType: String
			var url: URL?

			enum CodingKeys: String, CodingKey {
				case bitrate
				case contentType = "content_type"
				case url
			}

			init(from decoder: Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
				contentType = try container.decodeIfPresent(String.self, forKey: .contentType) ?? ""
				url = try container.decodeURLIfPresent(forKey: .url)
			}
		}
	}

	struct NoteTweet: Decodable, Equatable, Sendable {}

	struct Card: Decodable, Equatable, Sendable {
		var url: URL? = nil
		var bindingValues: [String: BindingValue] = [:]

		var destinationURL: URL? {
			stringValue(for: "card_url").flatMap(URL.init(string:)) ?? url
		}

		var title: String? {
			stringValue(for: "title")
		}

		var description: String? {
			stringValue(for: "description")
		}

		var domain: String? {
			stringValue(for: "vanity_url") ?? stringValue(for: "domain") ?? destinationURL?.host
		}

		var image: CardImage? {
			for key in [
				"summary_photo_image",
				"photo_image_full_size",
				"summary_photo_image_large",
				"photo_image_full_size_large",
				"thumbnail_image_large",
				"thumbnail_image",
			] {
				if let image = bindingValues[key]?.imageValue {
					return image
				}
			}
			return nil
		}

		var imageAltText: String? {
			stringValue(for: "summary_photo_image_alt_text") ?? stringValue(for: "photo_image_full_size_alt_text")
		}

		private func stringValue(for key: String) -> String? {
			bindingValues[key]?.stringValue
		}

		enum CodingKeys: String, CodingKey {
			case url
			case bindingValues = "binding_values"
		}

	}

	struct BindingValue: Decodable, Equatable, Sendable {
		var stringValue: String?
		var imageValue: CardImage?

		enum CodingKeys: String, CodingKey {
			case stringValue = "string_value"
			case imageValue = "image_value"
		}
	}

	struct CardImage: Decodable, Equatable, Sendable {
		var height: Int
		var width: Int
		var url: URL?

		var aspectRatio: Double {
			guard height > 0 else { return 16.0 / 9.0 }
			return Double(width) / Double(height)
		}

		enum CodingKeys: String, CodingKey {
			case height
			case width
			case url
		}

	}

	struct RawTextEntity: Equatable, Sendable {
		var indices: TextRange
		var displayText: String?
		var url: URL?
	}

	enum CodingKeys: String, CodingKey {
		case idString = "id_str"
		case text
		case createdAt = "created_at"
		case displayTextRange = "display_text_range"
		case entities
		case user
		case mediaDetails
		case card
		case quotedTweet = "quoted_tweet"
		case parent
		case inReplyToScreenName = "in_reply_to_screen_name"
		case inReplyToStatusIDString = "in_reply_to_status_id_str"
		case noteTweet = "note_tweet"
	}

}

extension Tweet {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		idString = try container.decode(String.self, forKey: .idString)
		text = try container.decode(String.self, forKey: .text)
		createdAt = try container.decode(Date.self, forKey: .createdAt)
		displayTextRange = try container.decode(TextRange.self, forKey: .displayTextRange)
		entities = try container.decodeIfPresent(Entities.self, forKey: .entities) ?? Entities()
		user = try container.decode(User.self, forKey: .user)
		mediaDetails = try container.decodeIfPresent([Media].self, forKey: .mediaDetails) ?? []
		card = try container.decodeIfPresent(Card.self, forKey: .card)
		quotedTweet = try container.decodeIfPresent(QuotedTweet.self, forKey: .quotedTweet)
		parent = try container.decodeIfPresent(ParentTweet.self, forKey: .parent)
		inReplyToScreenName = try container.decodeIfPresent(String.self, forKey: .inReplyToScreenName)
		inReplyToStatusIDString = try container.decodeIfPresent(String.self, forKey: .inReplyToStatusIDString)
		noteTweet = try container.decodeIfPresent(NoteTweet.self, forKey: .noteTweet)
	}
}

extension Tweet.User {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		name = try container.decode(String.self, forKey: .name)
		screenName = try container.decode(String.self, forKey: .screenName)
		profileImageURL = try container.decodeURLIfPresent(forKey: .profileImageURL)
		profileImageShape = try container.decodeIfPresent(ProfileImageShape.self, forKey: .profileImageShape) ?? .circle
		verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? false
		verifiedType = try container.decodeIfPresent(VerifiedType.self, forKey: .verifiedType)
		isBlueVerified = try container.decodeIfPresent(Bool.self, forKey: .isBlueVerified) ?? false
		highlightedLabel = try container.decodeIfPresent(HighlightedLabel.self, forKey: .highlightedLabel)
	}
}

extension Tweet.TextRange {
	init(from decoder: Decoder) throws {
		var container = try decoder.unkeyedContainer()
		start = try container.decode(Int.self)
		end = try container.decode(Int.self)
	}
}

extension Tweet.Entities {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		hashtags = try container.decodeIfPresent([Tweet.HashtagEntity].self, forKey: .hashtags) ?? []
		urls = try container.decodeIfPresent([Tweet.URLEntity].self, forKey: .urls) ?? []
		userMentions = try container.decodeIfPresent([Tweet.UserMentionEntity].self, forKey: .userMentions) ?? []
		symbols = try container.decodeIfPresent([Tweet.SymbolEntity].self, forKey: .symbols) ?? []
		media = try container.decodeIfPresent([Tweet.MediaEntity].self, forKey: .media) ?? []
	}
}

extension Tweet.URLEntity {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		displayURL = try container.decodeIfPresent(String.self, forKey: .displayURL) ?? ""
		expandedURL = try container.decodeURLIfPresent(forKey: .expandedURL)
		indices = try container.decode(Tweet.TextRange.self, forKey: .indices)
		url = try container.decodeURLIfPresent(forKey: .url)
	}
}

extension Tweet.Card {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		url = try container.decodeURLIfPresent(forKey: .url)
		bindingValues = try container.decodeIfPresent([String: Tweet.BindingValue].self, forKey: .bindingValues) ?? [:]
	}
}

extension Tweet.CardImage {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
		width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
		url = try container.decodeURLIfPresent(forKey: .url)
	}
}

protocol TweetTextProviding {
	var text: String { get }
	var displayTextRange: Tweet.TextRange { get }
	var entities: Tweet.Entities { get }
	var noteTweet: Tweet.NoteTweet? { get }
	var quotedTweetID: String? { get }
	var cardURL: URL? { get }
}

extension Tweet: TweetTextProviding {}

extension TweetTextProviding {
	var quotedTweetID: String? { nil }
	var cardURL: URL? { nil }
}

extension Tweet {
	var quotedTweetID: String? {
		quotedTweet?.idString
	}

	var cardURL: URL? {
		card?.destinationURL
	}
}

private extension URL {
	func isSameTweetCardURL(as other: URL) -> Bool {
		normalizedTweetCardURLString == other.normalizedTweetCardURLString
	}

	var normalizedTweetCardURLString: String {
		guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
			return absoluteString
		}

		components.scheme = components.scheme?.lowercased()
		components.host = components.host?.lowercased()

		if components.path.count > 1, components.path.hasSuffix("/") {
			components.path.removeLast()
		}

		return components.string ?? absoluteString
	}
}

private extension KeyedDecodingContainer {
	func decodeURLIfPresent(forKey key: Key) throws -> URL? {
		guard let string = try decodeIfPresent(String.self, forKey: key), !string.isEmpty else { return nil }
		return URL(string: string)
	}
}

#if DEBUG
extension Tweet {
	static let preview = Tweet(
		idString: "2038706412365533311",
		text: "weekend sidequest: needed to download +1TB from my Synology NAS, felt unnecessarily slow\n\nso I disassembled the macOS app, reverse-engineered the sync protocol from assembly, and built a Rust library (+ CLI)\n\nhttps://t.co/HPZwJNgzlb",
		createdAt: Date(timeIntervalSince1970: 1_774_900_460),
		displayTextRange: TextRange(start: 0, end: 232),
		entities: Entities(
			urls: [
				URLEntity(
					displayURL: "github.com/m1guelpf/sproto",
					expandedURL: URL(string: "https://github.com/m1guelpf/sproto"),
					indices: TextRange(start: 209, end: 232),
					url: URL(string: "https://t.co/HPZwJNgzlb")
				),
			]
		),
		user: User(
			name: "Miguel Piedrafita ✨",
			screenName: "m1guelpf",
			profileImageURL: URL(string: "https://pbs.twimg.com/profile_images/1905044735112486912/-P-N0qfO_normal.jpg"),
			isBlueVerified: true
		),
		card: Card(
			url: URL(string: "https://t.co/HPZwJNgzlb"),
			bindingValues: [
				"title": BindingValue(
					stringValue: "GitHub - m1guelpf/sproto: Rust client for the Synology Drive sync protocol, reverse-engineered from...",
					imageValue: nil
				),
				"description": BindingValue(
					stringValue: "Rust client for the Synology Drive sync protocol, reverse-engineered from the official macOS client. - m1guelpf/sproto",
					imageValue: nil
				),
				"domain": BindingValue(stringValue: "github.com", imageValue: nil),
				"vanity_url": BindingValue(stringValue: "github.com", imageValue: nil),
				"card_url": BindingValue(stringValue: "https://t.co/HPZwJNgzlb", imageValue: nil),
				"summary_photo_image": BindingValue(
					stringValue: nil,
					imageValue: CardImage(
						height: 314,
						width: 600,
						url: URL(string: "https://pbs.twimg.com/card_img/2046002619131256833/AtMyQSlh?format=jpg&name=600x314")
					)
				),
				"summary_photo_image_alt_text": BindingValue(
					stringValue: "Rust client for the Synology Drive sync protocol, reverse-engineered from the official macOS client. - m1guelpf/sproto",
					imageValue: nil
				),
			]
		)
	)
}
#endif
