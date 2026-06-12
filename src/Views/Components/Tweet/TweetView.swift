import SwiftUI

struct TweetView: View {
	enum Phase: Equatable {
		case idle
		case loading
		case loaded(Tweet)
		case failed(String)
	}

	private let id: String?

	@State private var phase: Phase

	init(id: String) {
		self.id = id
		_phase = State(initialValue: .idle)
	}

	init(tweet: Tweet) {
		id = nil
		_phase = State(initialValue: .loaded(tweet))
	}

	var body: some View {
		TweetPhaseContent(phase: phase)
			.frame(maxWidth: 550, alignment: .leading)
			.task(id: id) { await loadTweet() }
	}

	private func loadTweet() async {
		guard let id else { return }
		phase = .loading

		do {
			let tweet = try await Tweet.load(id)
			guard !Task.isCancelled else { return }
			phase = .loaded(tweet)
		} catch is CancellationError {
		} catch {
			phase = .failed(error.localizedDescription)
		}
	}
}

private struct TweetPhaseContent: View {
	var phase: TweetView.Phase

	var body: some View {
		switch phase {
			case .idle, .loading:
				TweetSkeletonView()

			case let .loaded(tweet):
				TweetCard(tweet: tweet)

			case let .failed(message):
				TweetUnavailableView(message: message)
		}
	}
}

private struct TweetCard: View {
	var tweet: Tweet

	@Namespace private var mediaTransitionNamespace
	@State private var fullScreenMedia: TweetMediaSelection?
	@State private var layout = TweetEmbedLayout.regular

	var body: some View {
		TweetCardContainer {
			TweetCardContent(
				tweet: tweet,
				layout: layout,
				mediaTransitionNamespace: mediaTransitionNamespace,
				onMediaTapped: showFullScreenMedia
			)
		}
		.onGeometryChange(for: TweetEmbedLayout.self) { proxy in
			TweetEmbedLayout(width: proxy.size.width)
		} action: { layout in
			self.layout = layout
		}
		.tweetMediaPresentation(item: $fullScreenMedia, transitionNamespace: mediaTransitionNamespace)
	}

	private func showFullScreenMedia(_ selection: TweetMediaSelection) {
		fullScreenMedia = selection
	}
}

private extension View {
	@ViewBuilder
	func tweetMediaPresentation(
		item: Binding<TweetMediaSelection?>,
		transitionNamespace: Namespace.ID
	) -> some View {
		#if os(iOS)
		fullScreenCover(item: item) { selection in
			TweetMediaFullScreenView(selection: selection, transitionNamespace: transitionNamespace)
		}
		#else
		sheet(item: item) { selection in
			TweetMediaFullScreenView(selection: selection, transitionNamespace: transitionNamespace)
				.frame(minWidth: 720, minHeight: 520)
		}
		#endif
	}
}

enum TweetEmbedLayout: Equatable, Sendable {
	case regular
	case compact

	init(width: CGFloat) {
		self = width <= 260 ? .compact : .regular
	}

	var primaryAvatarSize: CGFloat {
		self == .compact ? 20 : 24
	}

	var quotedAvatarSize: CGFloat {
		self == .compact ? 18 : 20
	}
}

private struct TweetCardContent: View {
	var tweet: Tweet
	var layout: TweetEmbedLayout
	var mediaTransitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	private var textSegments: [Tweet.TextSegment] {
		Tweet.textSegments(for: tweet)
	}

	private var bodyFont: Font {
		layout == .compact ? .footnote : .callout
	}

	private var bodyLineSpacing: CGFloat {
		layout == .compact ? 0 : 1
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let parent = tweet.parent {
				TweetReplyContext(tweet: parent, layout: layout)
			}

			TweetHeader(tweet: tweet, layout: layout)

			if tweet.parent == nil, let screenName = tweet.inReplyToScreenName {
				TweetReplyLabel(screenName: screenName, url: tweet.inReplyToURL)
			}

			if !textSegments.isEmpty || tweet.noteTweet != nil {
				TweetBodyText(
					segments: textSegments,
					showMoreURL: tweet.noteTweet == nil ? nil : tweet.url,
					font: bodyFont,
					lineSpacing: bodyLineSpacing
				)
			}

			if !tweet.mediaDetails.isEmpty {
				TweetMediaGrid(
					media: tweet.mediaDetails,
					isQuoted: false,
					transitionNamespace: mediaTransitionNamespace,
					onMediaTapped: onMediaTapped
				)
			}

			if let card = tweet.card {
				TweetURLPreviewCard(card: card)
			}

			if let quotedTweet = tweet.quotedTweet {
				QuotedTweetView(
					tweet: quotedTweet,
					layout: layout,
					transitionNamespace: mediaTransitionNamespace,
					onMediaTapped: onMediaTapped
				)
			}

			TweetMetadataRow(tweet: tweet)
		}
	}
}

struct TweetCardContainer<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
		content
			.padding(12)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(.background)
			.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.stroke(.separator, lineWidth: 1)
			}
	}
}

private struct TweetSkeletonView: View {
	var body: some View {
		TweetCardContainer {
			VStack(alignment: .leading, spacing: 12) {
				TweetSkeletonHeader()

				VStack(alignment: .leading, spacing: 7) {
					RoundedRectangle(cornerRadius: 3)
						.frame(height: 15)
					RoundedRectangle(cornerRadius: 3)
						.frame(maxWidth: 360)
						.frame(height: 15)
				}
				.foregroundStyle(.secondary.opacity(0.18))
			}
		}
		.redacted(reason: .placeholder)
	}
}

private struct TweetSkeletonHeader: View {
	var body: some View {
		HStack(spacing: 10) {
			Circle()
				.fill(.secondary.opacity(0.16))
				.frame(width: 48, height: 48)

			VStack(alignment: .leading, spacing: 6) {
				RoundedRectangle(cornerRadius: 3)
					.frame(width: 140, height: 13)
				RoundedRectangle(cornerRadius: 3)
					.frame(width: 92, height: 11)
			}
			.foregroundStyle(.secondary.opacity(0.18))
		}
	}
}

struct TweetUnavailableView: View {
	var message: String

	var body: some View {
		TweetCardContainer {
			HStack(spacing: 10) {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.secondary)

				Text(message)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}

#Preview {
	TweetView(tweet: .preview)
		.padding()
}

#Preview("Tweet ID") {
	@Previewable @State var tweetID = "2047436034640695542"

	VStack(alignment: .leading, spacing: 12) {
		TextField("Tweet ID", text: $tweetID)
			.textFieldStyle(.roundedBorder)
			.font(.callout.monospacedDigit())

		TweetView(id: tweetID)
	}
	.padding()
}
