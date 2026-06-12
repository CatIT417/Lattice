import AVKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TweetMediaFullScreenView: View {
	@Environment(\.dismiss) private var dismiss

	var selection: TweetMediaSelection
	var transitionNamespace: Namespace.ID

	@State private var selectedMediaID: Tweet.Media.ID
	@State private var loadedImageByMediaID: [Tweet.Media.ID: TweetSharePayload] = [:]
	@State private var downloadedVideoByMediaID: [Tweet.Media.ID: TweetSharePayload] = [:]
	@State private var isPreparingShare = false
	#if canImport(UIKit)
	@State private var presentedSharePayload: TweetSharePayload?
	#endif

	init(selection: TweetMediaSelection, transitionNamespace: Namespace.ID) {
		self.selection = selection
		self.transitionNamespace = transitionNamespace
		_selectedMediaID = State(initialValue: selection.selectedMediaID)
	}

	var body: some View {
		content
			.tweetMediaZoomTransition(sourceID: selectedMediaID, in: transitionNamespace)
		#if canImport(UIKit)
			.sheet(item: $presentedSharePayload) { payload in
				TweetActivityView(payload: payload)
					.ignoresSafeArea()
			}
		#endif
	}

	private var selectedMedia: Tweet.Media? {
		selection.media.first { $0.id == selectedMediaID }
	}

	private var sharePayload: TweetSharePayload? {
		loadedImageByMediaID[selectedMediaID] ?? downloadedVideoByMediaID[selectedMediaID]
	}

	private var canShareSelectedMedia: Bool {
		sharePayload != nil || selectedMedia?.playableVideoURL != nil
	}

	private var content: some View {
		ZStack(alignment: .top) {
			Color.black
				.ignoresSafeArea()

			mediaPager

			TweetMediaFullScreenControls(
				sharePayload: sharePayload,
				canShare: canShareSelectedMedia,
				isPreparingShare: isPreparingShare,
				close: dismiss.callAsFunction,
				share: share
			)
			.padding(.horizontal, 16)
			.safeAreaPadding(.top, 8)
		}
	}

	@ViewBuilder
	private var mediaPager: some View {
		#if canImport(UIKit)
		TabView(selection: $selectedMediaID) {
			ForEach(selection.media) { media in
				TweetMediaFullScreenPage(media: media, onImageLoaded: imageLoaded)
					.tag(media.id)
			}
		}
		.tabViewStyle(.page(indexDisplayMode: selection.media.count > 1 ? .automatic : .never))
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.ignoresSafeArea()
		#elseif canImport(AppKit)
		ZStack {
			if let selectedMedia {
				TweetMediaFullScreenPage(media: selectedMedia, onImageLoaded: imageLoaded)
			}

			if selection.media.count > 1 {
				TweetMediaFullScreenPagerControls(
					canSelectPrevious: canSelectPreviousMedia,
					canSelectNext: canSelectNextMedia,
					selectPrevious: selectPreviousMedia,
					selectNext: selectNextMedia
				)
				.padding(.horizontal, 16)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.black)
		#endif
	}

	private func share() {
		guard !isPreparingShare else { return }

		Task {
			await prepareAndShareSelectedMedia()
		}
	}

	private func imageLoaded(mediaID: Tweet.Media.ID, image: PlatformImage) {
		loadedImageByMediaID[mediaID] = TweetSharePayload(mediaID: mediaID, item: .image(image))
	}

	private var selectedMediaIndex: Int? {
		selection.media.firstIndex { $0.id == selectedMediaID }
	}

	private var canSelectPreviousMedia: Bool {
		guard let selectedMediaIndex else { return false }
		return selectedMediaIndex > 0
	}

	private var canSelectNextMedia: Bool {
		guard let selectedMediaIndex else { return false }
		return selectedMediaIndex < selection.media.index(before: selection.media.endIndex)
	}

	private func selectPreviousMedia() {
		guard let selectedMediaIndex, selectedMediaIndex > 0 else { return }
		selectedMediaID = selection.media[selection.media.index(before: selectedMediaIndex)].id
	}

	private func selectNextMedia() {
		guard let selectedMediaIndex, selectedMediaIndex < selection.media.index(before: selection.media.endIndex) else { return }
		selectedMediaID = selection.media[selection.media.index(after: selectedMediaIndex)].id
	}

	@MainActor
	private func prepareAndShareSelectedMedia() async {
		if let sharePayload {
			present(sharePayload)
			return
		}

		guard let selectedMedia, let videoURL = selectedMedia.playableVideoURL else { return }

		isPreparingShare = true
		defer { isPreparingShare = false }

		do {
			let fileURL = try await downloadVideo(from: videoURL, mediaID: selectedMedia.id)
			let payload = TweetSharePayload(mediaID: selectedMedia.id, item: .file(fileURL))
			downloadedVideoByMediaID[selectedMedia.id] = payload
			present(payload)
		} catch {}
	}

	private func present(_ payload: TweetSharePayload) {
		#if canImport(UIKit)
		presentedSharePayload = payload
		#endif
	}

	private func downloadVideo(from sourceURL: URL, mediaID: Tweet.Media.ID) async throws -> URL {
		let (downloadURL, _) = try await URLSession.shared.download(from: sourceURL)
		let fileExtension = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
		let destinationURL = FileManager.default
			.temporaryDirectory
			.appendingPathComponent("tweet-\(mediaID.safeFilenameComponent)-\(UUID().uuidString)")
			.appendingPathExtension(fileExtension)

		try FileManager.default.copyItem(at: downloadURL, to: destinationURL)
		return destinationURL
	}
}

private struct TweetMediaFullScreenPagerControls: View {
	var canSelectPrevious: Bool
	var canSelectNext: Bool
	var selectPrevious: () -> Void
	var selectNext: () -> Void

	var body: some View {
		HStack {
			Button(action: selectPrevious) {
				TweetFullScreenControlLabel(systemName: "chevron.left")
			}
			.buttonStyle(.plain)
			.disabled(!canSelectPrevious)
			.opacity(canSelectPrevious ? 1 : 0)
			.accessibilityLabel("Previous media")

			Spacer()

			Button(action: selectNext) {
				TweetFullScreenControlLabel(systemName: "chevron.right")
			}
			.buttonStyle(.plain)
			.disabled(!canSelectNext)
			.opacity(canSelectNext ? 1 : 0)
			.accessibilityLabel("Next media")
		}
	}
}

private extension View {
	@ViewBuilder
	func tweetMediaZoomTransition(sourceID: Tweet.Media.ID, in namespace: Namespace.ID) -> some View {
		#if os(iOS)
		navigationTransition(.zoom(sourceID: sourceID, in: namespace))
		#else
		self
		#endif
	}
}

private struct TweetMediaFullScreenControls: View {
	var sharePayload: TweetSharePayload?
	var canShare: Bool
	var isPreparingShare: Bool
	var close: () -> Void
	var share: () -> Void

	var body: some View {
		HStack {
			Button(action: close) {
				TweetFullScreenControlLabel(systemName: "xmark")
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Close media")

			Spacer()

			TweetMediaShareButton(
				sharePayload: sharePayload,
				canShare: canShare,
				isPreparingShare: isPreparingShare,
				share: share
			)
		}
	}
}

private struct TweetMediaShareButton: View {
	var sharePayload: TweetSharePayload?
	var canShare: Bool
	var isPreparingShare: Bool
	var share: () -> Void

	var body: some View {
		#if canImport(UIKit)
		Button(action: share) {
			TweetFullScreenControlLabel(systemName: "square.and.arrow.up", isLoading: isPreparingShare)
		}
		.buttonStyle(.plain)
		.disabled(!canShare || isPreparingShare)
		.opacity(canShare ? 1 : 0.55)
		.accessibilityLabel("Share media")
		#elseif canImport(AppKit)
		if let sharePayload {
			switch sharePayload.item {
				case let .image(image):
					ShareLink(item: image, preview: SharePreview("Image", image: Image(nsImage: image))) {
						TweetFullScreenControlLabel(systemName: "square.and.arrow.up", isLoading: false)
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Share media")

				case let .file(url):
					ShareLink(item: url, preview: SharePreview("Video")) {
						TweetFullScreenControlLabel(systemName: "square.and.arrow.up", isLoading: false)
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Share media")
			}
		} else {
			Button(action: share) {
				TweetFullScreenControlLabel(systemName: "square.and.arrow.up", isLoading: isPreparingShare)
			}
			.buttonStyle(.plain)
			.disabled(!canShare || isPreparingShare)
			.opacity(canShare ? 1 : 0.55)
			.accessibilityLabel("Share media")
		}
		#endif
	}
}

private struct TweetFullScreenControlLabel: View {
	var systemName: String
	var isLoading = false

	var body: some View {
		ZStack {
			if isLoading {
				ProgressView()
					.tint(.white)
					.controlSize(.small)
			} else {
				Image(systemName: systemName)
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(.white)
			}
		}
		.frame(width: 44, height: 44)
		.background(.black.opacity(0.48), in: Circle())
		.contentShape(Circle())
	}
}

private struct TweetMediaFullScreenPage: View {
	var media: Tweet.Media
	var onImageLoaded: (Tweet.Media.ID, PlatformImage) -> Void

	@State private var image: PlatformImage?
	@State private var imageLoadFailed = false

	private var fullSizeURL: URL? {
		media.originalImageURL ?? media.imageURL
	}

	var body: some View {
		switch media.kind {
			case .photo:
				imagePage

			case .video, .animatedGIF:
				if let url = media.playableVideoURL {
					TweetMediaFullScreenVideoPage(url: url)
				} else {
					imagePage
				}
		}
	}

	private var imagePage: some View {
		Group {
			if let image {
				ZoomablePlatformImage(image: image)
			} else if imageLoadFailed {
				TweetMediaFullScreenError(message: "Media could not be loaded.")
			} else {
				ProgressView()
					.tint(.white)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.black)
		.task(id: fullSizeURL) {
			await loadImage()
		}
	}

	@MainActor private func loadImage() async {
		image = nil
		imageLoadFailed = false

		guard let fullSizeURL else {
			imageLoadFailed = true
			return
		}

		do {
			let (data, _) = try await URLSession.shared.data(from: fullSizeURL)
			guard !Task.isCancelled else { return }

			#if canImport(UIKit)
			let loadedImage = UIImage(data: data)
			#elseif canImport(AppKit)
			let loadedImage = NSImage(data: data)
			#endif

			guard let loadedImage else {
				imageLoadFailed = true
				return
			}

			image = loadedImage
			imageLoadFailed = false
			onImageLoaded(media.id, loadedImage)
		} catch {
			if !Task.isCancelled {
				imageLoadFailed = true
			}
		}
	}
}

private struct TweetMediaFullScreenError: View {
	var message = "Image could not be loaded."

	var body: some View {
		VStack(spacing: 10) {
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.title2)

			Text(message)
				.font(.subheadline)
		}
		.foregroundStyle(.white.opacity(0.82))
	}
}

private struct TweetMediaFullScreenVideoPage: View {
	var url: URL

	@State private var player: AVPlayer?

	var body: some View {
		Group {
			if let player {
				VideoPlayer(player: player)
					.background(.black)
			} else {
				ProgressView()
					.tint(.white)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.black)
		.task(id: url) { preparePlayer() }
		.onDisappear {
			player?.pause()
		}
	}

	@MainActor
	private func preparePlayer() {
		player?.pause()
		player = AVPlayer(url: url)
		player?.play()
	}
}

struct TweetSharePayload: Identifiable {
	enum Item {
		case image(PlatformImage)
		case file(URL)
	}

	var mediaID: Tweet.Media.ID
	var item: Item

	var id: Tweet.Media.ID {
		mediaID
	}

	#if canImport(UIKit)
	var activityItem: Any {
		switch item {
			case let .image(image): image
			case let .file(url): url
		}
	}
	#endif
}

#if canImport(UIKit)
private struct TweetActivityView: UIViewControllerRepresentable {
	var payload: TweetSharePayload

	func makeUIViewController(context _: Context) -> UIActivityViewController {
		UIActivityViewController(activityItems: [payload.activityItem], applicationActivities: nil)
	}

	func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
#endif

private extension String {
	var safeFilenameComponent: String {
		map { character in
			character.isLetter || character.isNumber ? String(character) : "-"
		}
		.joined()
	}
}
