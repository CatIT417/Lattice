import NukeUI
import SwiftUI

struct TweetReplyContext: View {
	var tweet: Tweet.ParentTweet
	var layout: TweetEmbedLayout

	private var avatarSize: CGFloat {
		layout.primaryAvatarSize
	}

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			TweetAvatar(user: tweet.user, size: avatarSize)
				.frame(width: avatarSize)

			VStack(alignment: .leading, spacing: 5) {
				TweetReplyContextHeader(tweet: tweet, layout: layout)

				if let replyTarget {
					TweetReplyLabel(screenName: replyTarget.screenName, url: replyTarget.url)
				}

				let textSegments = Tweet.textSegments(for: tweet)
				if !textSegments.isEmpty || tweet.noteTweet != nil {
					TweetBodyText(
						segments: textSegments,
						showMoreURL: tweet.noteTweet == nil ? nil : tweet.url,
						font: layout == .compact ? .caption : .subheadline,
						lineSpacing: 0,
						lineLimit: layout == .compact ? 4 : 3
					)
					.foregroundStyle(.primary)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.overlay(alignment: .topLeading) {
			Rectangle()
				.fill(.separator)
				.frame(width: 2)
				.padding(.top, avatarSize + 5)
				.padding(.leading, (avatarSize - 2) / 2)
				.allowsHitTesting(false)
		}
		.padding(.bottom, 2)
	}

	private var replyTarget: (screenName: String, url: URL?)? {
		if let screenName = tweet.inReplyToScreenName {
			return (screenName, tweet.inReplyToURL)
		}

		if let quotedTweet = tweet.quotedTweet {
			return (quotedTweet.user.screenName, quotedTweet.url)
		}

		return nil
	}
}

private struct TweetReplyContextHeader: View {
	var tweet: Tweet.ParentTweet
	var layout: TweetEmbedLayout

	var body: some View {
		Link(destination: tweet.url) {
			TweetUserByline(
				user: tweet.user,
				date: layout == .regular ? tweet.createdAt : nil,
				nameFont: layout == .compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold),
				usernameFont: .caption,
				showsHighlightedLabel: layout == .regular
			)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.buttonStyle(.plain)
		.accessibilityLabel("\(tweet.user.name), @\(tweet.user.screenName)")
	}
}

struct TweetReplyLabel: View {
	var screenName: String
	var url: URL?

	var body: some View {
		Link(destination: url ?? URL(string: "https://x.com/\(screenName)")!) {
			Text("Replying to @\(screenName)")
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.tail)
		}
		.buttonStyle(.plain)
	}
}

struct TweetHeader: View {
	var tweet: Tweet
	var layout: TweetEmbedLayout

	var body: some View {
		TweetUserHeader(
			user: tweet.user,
			avatarSize: layout.primaryAvatarSize,
			nameFont: layout == .compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold),
			usernameFont: layout == .compact ? .caption : .subheadline,
			showsHighlightedLabel: layout == .regular
		)
	}
}

struct TweetUserHeader: View {
	var user: Tweet.User
	var avatarSize: CGFloat
	var nameFont: Font
	var usernameFont: Font
	var showsHighlightedLabel = true

	var body: some View {
		Link(destination: user.url) {
			HStack(alignment: .center, spacing: 7) {
				TweetAvatar(user: user, size: avatarSize)

				TweetUserByline(
					user: user,
					nameFont: nameFont,
					usernameFont: usernameFont,
					showsHighlightedLabel: showsHighlightedLabel
				)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel("\(user.name), @\(user.screenName)")
	}
}

struct TweetUserByline: View {
	var user: Tweet.User
	var date: Date?
	var nameFont: Font
	var usernameFont: Font
	var showsHighlightedLabel = true

	init(
		user: Tweet.User,
		date: Date? = nil,
		nameFont: Font,
		usernameFont: Font,
		showsHighlightedLabel: Bool = true
	) {
		self.user = user
		self.date = date
		self.nameFont = nameFont
		self.usernameFont = usernameFont
		self.showsHighlightedLabel = showsHighlightedLabel
	}

	var body: some View {
		HStack(spacing: 4) {
			Text(user.name)
				.font(nameFont)
				.foregroundStyle(.primary)
				.lineLimit(1)
				.truncationMode(.tail)
				.layoutPriority(1)

			VerifiedBadge(user: user)

			if showsHighlightedLabel {
				TweetHighlightedLabelBadge(label: user.highlightedLabel)
			}

			Text("@\(user.screenName)")
				.font(usernameFont)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.tail)
				.minimumScaleFactor(0.9)

			if let date {
				Text("· \(date.tweetDateString)")
					.font(usernameFont)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
	}
}

private struct TweetHighlightedLabelBadge: View {
	var label: Tweet.User.HighlightedLabel?

	var body: some View {
		if let label, let url = label.badge?.url {
			LazyImage(url: url) { state in
				if let image = state.image {
					image
						.resizable()
						.scaledToFill()
				} else {
					RoundedRectangle(cornerRadius: 3, style: .continuous)
						.fill(.secondary.opacity(0.14))
				}
			}
			.frame(width: 16, height: 16)
			.clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
			.accessibilityLabel(label.labelDescription ?? "Affiliation")
		}
	}
}

struct TweetBodyText: View {
	var segments: [Tweet.TextSegment]
	var showMoreURL: URL?
	var font: Font
	var lineSpacing: CGFloat
	var lineLimit: Int?

	var body: some View {
		Text(attributedText)
			.font(font)
			.lineSpacing(lineSpacing)
			.lineLimit(lineLimit)
			.fixedSize(horizontal: false, vertical: true)
			.environment(\.openURL, OpenURLAction { url in
				.systemAction(url)
			})
	}

	private var attributedText: AttributedString {
		var text = AttributedString()

		for segment in segments {
			var chunk = AttributedString(segment.text)
			if let url = segment.url {
				chunk.link = url
				chunk.foregroundColor = .blue
			}
			text.append(chunk)
		}

		if let showMoreURL {
			var showMore = AttributedString(" Show more")
			showMore.link = showMoreURL
			showMore.foregroundColor = .blue
			text.append(showMore)
		}

		return text
	}
}

struct TweetMetadataRow: View {
	var tweet: Tweet

	var body: some View {
		Link(tweet.createdAt.tweetTimestampString, destination: tweet.url)
			.foregroundStyle(.secondary)
			.font(.caption)
	}
}

struct QuotedTweetView: View {
	var tweet: Tweet.QuotedTweet
	var layout: TweetEmbedLayout
	var transitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	var body: some View {
		QuotedTweetContent(
			tweet: tweet,
			textSegments: textSegments,
			layout: layout,
			transitionNamespace: transitionNamespace,
			onMediaTapped: onMediaTapped
		)
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.background)
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(.separator, lineWidth: 1)
		}
	}

	private var textSegments: [Tweet.TextSegment] {
		Tweet.textSegments(for: tweet)
	}
}

private struct QuotedTweetContent: View {
	var tweet: Tweet.QuotedTweet
	var textSegments: [Tweet.TextSegment]
	var layout: TweetEmbedLayout
	var transitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	var body: some View {
		if tweet.mediaDetails.count == 1, let media = tweet.mediaDetails.first, !textSegments.isEmpty {
			ViewThatFits(in: .horizontal) {
				QuotedTweetHorizontalContent(
					tweet: tweet,
					media: media,
					textSegments: textSegments,
					layout: layout,
					transitionNamespace: transitionNamespace,
					onMediaTapped: onMediaTapped
				)

				QuotedTweetVerticalContent(
					tweet: tweet,
					textSegments: textSegments,
					layout: layout,
					transitionNamespace: transitionNamespace,
					onMediaTapped: onMediaTapped
				)
			}
		} else {
			QuotedTweetVerticalContent(
				tweet: tweet,
				textSegments: textSegments,
				layout: layout,
				transitionNamespace: transitionNamespace,
				onMediaTapped: onMediaTapped
			)
		}
	}
}

private struct QuotedTweetHorizontalContent: View {
	var tweet: Tweet.QuotedTweet
	var media: Tweet.Media
	var textSegments: [Tweet.TextSegment]
	var layout: TweetEmbedLayout
	var transitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			TweetMediaThumbnail(media: media, transitionNamespace: transitionNamespace, onMediaTapped: onMediaTapped)
				.frame(width: 94, height: 94)

			QuotedTweetTextStack(tweet: tweet, textSegments: textSegments, layout: layout)
				.frame(width: 340, alignment: .leading)
		}
		.frame(width: 444, alignment: .leading)
	}
}

private struct QuotedTweetTextStack: View {
	var tweet: Tweet.QuotedTweet
	var textSegments: [Tweet.TextSegment]
	var layout: TweetEmbedLayout

	var body: some View {
		VStack(alignment: .leading, spacing: 7) {
			TweetUserHeader(
				user: tweet.user,
				avatarSize: layout.quotedAvatarSize,
				nameFont: .caption.weight(.semibold),
				usernameFont: .caption,
				showsHighlightedLabel: layout == .regular
			)

			if let screenName = tweet.inReplyToScreenName {
				TweetReplyLabel(screenName: screenName, url: tweet.inReplyToURL)
			}

			if !textSegments.isEmpty || tweet.noteTweet != nil {
				TweetBodyText(
					segments: textSegments,
					showMoreURL: tweet.noteTweet == nil ? nil : tweet.url,
					font: layout == .compact ? .caption : .subheadline,
					lineSpacing: layout == .compact ? 1 : 2
				)
				.foregroundStyle(.primary)
			}
		}
	}
}

private struct QuotedTweetVerticalContent: View {
	var tweet: Tweet.QuotedTweet
	var textSegments: [Tweet.TextSegment]
	var layout: TweetEmbedLayout
	var transitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			QuotedTweetTextStack(tweet: tweet, textSegments: textSegments, layout: layout)

			if !tweet.mediaDetails.isEmpty {
				TweetMediaGrid(
					media: tweet.mediaDetails,
					isQuoted: true,
					transitionNamespace: transitionNamespace,
					onMediaTapped: onMediaTapped
				)
			}
		}
	}
}

struct TweetAvatar: View {
	var user: Tweet.User
	var size: CGFloat

	var body: some View {
		let cornerRadius = user.profileImageShape == .square ? 6.0 : size / 2

		ZStack {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.fill(.secondary.opacity(0.14))

			LazyImage(url: user.highResolutionProfileImageURL) { state in
				if let image = state.image {
					image
						.resizable()
						.scaledToFill()
				} else {
					Text(user.name.prefix(1))
						.font(.system(size: size * 0.4, weight: .semibold))
						.foregroundStyle(.secondary)
				}
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.stroke(.black.opacity(0.05), lineWidth: 1)
		}
	}
}

private struct VerifiedBadge: View {
	var user: Tweet.User

	var body: some View {
		if user.verified || user.isBlueVerified || user.verifiedType != nil {
			Image(systemName: "checkmark.seal.fill")
				.imageScale(.small)
				.foregroundStyle(color)
				.accessibilityLabel("Verified")
		}
	}

	private var color: Color {
		switch user.verifiedType {
			case .business: .yellow
			case .government: .gray
			case nil: .blue
		}
	}
}

extension Date {
	var tweetDateString: String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "MMM d, yyyy"
		return formatter.string(from: self)
	}

	var tweetTimestampString: String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")

		formatter.dateFormat = "h:mm a"
		let time = formatter.string(from: self)

		formatter.dateFormat = "MMM d, yyyy"
		let date = formatter.string(from: self)

		return "\(time) · \(date)"
	}
}
