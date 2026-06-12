import NukeUI
import SwiftUI

struct TweetMediaSelection: Equatable, Identifiable {
	var media: [Tweet.Media]
	var selectedMediaID: Tweet.Media.ID

	var id: String {
		selectedMediaID
	}

	init(media: [Tweet.Media], selectedMedia: Tweet.Media) {
		self.media = media.isEmpty ? [selectedMedia] : media
		selectedMediaID = self.media.contains { $0.id == selectedMedia.id } ? selectedMedia.id : self.media[0].id
	}
}

struct TweetURLPreviewCard: View {
	var card: Tweet.Card

	var body: some View {
		if let destinationURL = card.destinationURL {
			Link(destination: destinationURL) {
				VStack(alignment: .leading, spacing: 0) {
					if let image = card.image {
						TweetURLPreviewImage(image: image, altText: card.imageAltText)
					}

					TweetURLPreviewText(card: card)
						.padding(10)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(.background)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				.overlay {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.stroke(.separator, lineWidth: 1)
				}
			}
			.buttonStyle(.plain)
			.accessibilityLabel(card.title ?? card.domain ?? "URL preview")
		}
	}
}

private struct TweetURLPreviewText: View {
	var card: Tweet.Card

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			if let domain = card.domain {
				Text(domain)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			if let title = card.title {
				Text(title)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(3)
					.fixedSize(horizontal: false, vertical: true)
			}

			if let description = card.description {
				Text(description)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}
}

private struct TweetURLPreviewImage: View {
	var image: Tweet.CardImage
	var altText: String?

	var body: some View {
		ZStack {
			Rectangle()
				.fill(.secondary.opacity(0.12))

			if let url = image.url {
				LazyImage(url: url) { state in
					if let image = state.image {
						image
							.resizable()
							.scaledToFill()
					} else {
						Rectangle()
							.fill(.secondary.opacity(0.12))
							.overlay {
								ProgressView()
									.controlSize(.small)
							}
					}
				}
			}
		}
		.aspectRatio(CGFloat(image.aspectRatio), contentMode: .fit)
		.clipped()
		.accessibilityLabel(altText ?? "Link preview image")
	}
}

struct TweetMediaGrid: View {
	var media: [Tweet.Media]
	var isQuoted: Bool
	var transitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	private var visibleMedia: [Tweet.Media] {
		Array(media.prefix(4))
	}

	var body: some View {
		let media = visibleMedia

		if !media.isEmpty {
			TweetMediaGridLayout(itemCount: media.count, aspectRatio: aspectRatio(for: media)) {
				ForEach(media) { item in
					TweetMediaItem(
						media: item,
						fullScreenMedia: media,
						transitionNamespace: transitionNamespace,
						onMediaTapped: onMediaTapped
					)
				}
			}
			.frame(maxWidth: .infinity)
			.clipShape(RoundedRectangle(cornerRadius: isQuoted ? 8 : 12, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: isQuoted ? 8 : 12, style: .continuous)
					.stroke(.separator, lineWidth: 1)
			}
		}
	}

	private func aspectRatio(for media: [Tweet.Media]) -> CGFloat {
		media.count == 1 ? CGFloat(media[0].aspectRatio) : CGFloat(16.0 / 9.0)
	}
}

private struct TweetMediaGridLayout: Layout {
	var itemCount: Int
	var aspectRatio: CGFloat
	var spacing: CGFloat = 2

	func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
		let width = proposal.width ?? proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 0)).width
		guard width > 0, aspectRatio > 0 else { return .zero }
		return CGSize(width: width, height: width / aspectRatio)
	}

	func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
		let frames = itemFrames(in: bounds, count: min(itemCount, subviews.count))

		for (index, frame) in frames.enumerated() {
			subviews[index].place(
				at: CGPoint(x: frame.midX, y: frame.midY),
				anchor: .center,
				proposal: ProposedViewSize(width: frame.width, height: frame.height)
			)
		}
	}

	private func itemFrames(in bounds: CGRect, count: Int) -> [CGRect] {
		switch count {
			case 1:
				[bounds]

			case 2:
				twoColumnFrames(in: bounds)

			case 3:
				threeImageFrames(in: bounds)

			default:
				fourImageFrames(in: bounds)
		}
	}

	private func twoColumnFrames(in bounds: CGRect) -> [CGRect] {
		let columnWidth = (bounds.width - spacing) / 2
		return [
			CGRect(x: bounds.minX, y: bounds.minY, width: columnWidth, height: bounds.height),
			CGRect(x: bounds.minX + columnWidth + spacing, y: bounds.minY, width: columnWidth, height: bounds.height),
		]
	}

	private func threeImageFrames(in bounds: CGRect) -> [CGRect] {
		let leftWidth = (bounds.width - spacing) / 2
		let rightWidth = bounds.width - leftWidth - spacing
		let rowHeight = (bounds.height - spacing) / 2
		let rightX = bounds.minX + leftWidth + spacing

		return [
			CGRect(x: bounds.minX, y: bounds.minY, width: leftWidth, height: bounds.height),
			CGRect(x: rightX, y: bounds.minY, width: rightWidth, height: rowHeight),
			CGRect(x: rightX, y: bounds.minY + rowHeight + spacing, width: rightWidth, height: rowHeight),
		]
	}

	private func fourImageFrames(in bounds: CGRect) -> [CGRect] {
		let columnWidth = (bounds.width - spacing) / 2
		let rowHeight = (bounds.height - spacing) / 2
		let rightX = bounds.minX + columnWidth + spacing
		let bottomY = bounds.minY + rowHeight + spacing

		return [
			CGRect(x: bounds.minX, y: bounds.minY, width: columnWidth, height: rowHeight),
			CGRect(x: rightX, y: bounds.minY, width: columnWidth, height: rowHeight),
			CGRect(x: bounds.minX, y: bottomY, width: columnWidth, height: rowHeight),
			CGRect(x: rightX, y: bottomY, width: columnWidth, height: rowHeight),
		]
	}
}

private struct TweetMediaItem: View {
	var media: Tweet.Media
	var fullScreenMedia: [Tweet.Media]
	var transitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	var body: some View {
		Button {
			onMediaTapped(TweetMediaSelection(media: fullScreenMedia, selectedMedia: media))
		} label: {
			TweetMediaCell(media: media)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(accessibilityLabel)
		.matchedTransitionSource(id: media.id, in: transitionNamespace)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var accessibilityLabel: String {
		switch media.kind {
			case .photo: "Open image"
			case .video: "Open video"
			case .animatedGIF: "Open GIF"
		}
	}
}

struct TweetMediaThumbnail: View {
	var media: Tweet.Media
	var transitionNamespace: Namespace.ID
	var onMediaTapped: (TweetMediaSelection) -> Void

	var body: some View {
		TweetMediaItem(
			media: media,
			fullScreenMedia: [media],
			transitionNamespace: transitionNamespace,
			onMediaTapped: onMediaTapped
		)
		.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.stroke(.separator, lineWidth: 1)
		}
	}
}

private struct TweetMediaCell: View {
	var media: Tweet.Media

	var body: some View {
		Rectangle()
			.fill(.secondary.opacity(0.12))
			.overlay {
				image
			}
			.overlay {
				if media.kind != .photo {
					TweetMediaPlayBadge(kind: media.kind)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.clipped()
	}

	@ViewBuilder
	private var image: some View {
		if let imageURL = media.imageURL {
			Rectangle()
				.fill(.clear)
				.overlay {
					LazyImage(url: imageURL) { state in
						if let image = state.image {
							image
								.resizable()
								.scaledToFill()
						} else {
							Rectangle()
								.fill(.secondary.opacity(0.12))
								.overlay {
									ProgressView()
										.controlSize(.small)
								}
						}
					}
				}
				.clipped()
		}
	}
}

private struct TweetMediaPlayBadge: View {
	var kind: Tweet.Media.Kind

	var body: some View {
		if kind == .animatedGIF {
			Image(systemName: "gif")
				.font(.system(size: 14, weight: .bold))
				.foregroundStyle(.white)
				.padding(.horizontal, 8)
				.padding(.vertical, 5)
				.background(.black.opacity(0.68), in: Capsule())
				.accessibilityLabel("GIF")
		} else {
			ZStack {
				Circle()
					.fill(.black.opacity(0.68))

				Image(systemName: "play.fill")
					.font(.system(size: 20, weight: .bold))
					.foregroundStyle(.white)
					.offset(x: 2)
			}
			.frame(width: 54, height: 54)
			.accessibilityLabel("Video")
		}
	}
}
