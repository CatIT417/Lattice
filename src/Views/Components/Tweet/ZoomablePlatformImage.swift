import SwiftUI

#if canImport(UIKit)
import UIKit

struct ZoomablePlatformImage: UIViewRepresentable {
	var image: PlatformImage

	func makeUIView(context _: Context) -> ZoomingImageScrollView {
		ZoomingImageScrollView()
	}

	func updateUIView(_ scrollView: ZoomingImageScrollView, context _: Context) {
		scrollView.setImage(image)
	}
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
	private let imageView = UIImageView()
	private var currentImage: UIImage?
	private var lastBoundsSize: CGSize = .zero
	private var needsImageLayout = true

	override init(frame: CGRect) {
		super.init(frame: frame)

		backgroundColor = .black
		contentInsetAdjustmentBehavior = .never
		decelerationRate = .fast
		delegate = self
		showsHorizontalScrollIndicator = false
		showsVerticalScrollIndicator = false
		bouncesZoom = true
		minimumZoomScale = 1
		maximumZoomScale = 6
		panGestureRecognizer.delegate = self

		imageView.contentMode = .scaleAspectFit
		imageView.isUserInteractionEnabled = true
		addSubview(imageView)

		let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
		doubleTap.numberOfTapsRequired = 2
		addGestureRecognizer(doubleTap)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func setImage(_ image: UIImage) {
		guard currentImage !== image else { return }

		currentImage = image
		imageView.image = image
		needsImageLayout = true
		setNeedsLayout()
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		if needsImageLayout || bounds.size != lastBoundsSize {
			layoutImageForCurrentBounds()
			lastBoundsSize = bounds.size
			needsImageLayout = false
		} else {
			centerImage()
		}
	}

	func viewForZooming(in _: UIScrollView) -> UIView? {
		imageView
	}

	func scrollViewDidZoom(_: UIScrollView) {
		centerImage()
	}

	override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		if gestureRecognizer === panGestureRecognizer, zoomScale <= minimumZoomScale {
			return false
		}

		return true
	}

	private func layoutImageForCurrentBounds() {
		guard let image = imageView.image, bounds.width > 0, bounds.height > 0, image.size.width > 0, image.size.height > 0 else { return }

		let fitScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
		let fittedSize = CGSize(width: image.size.width * fitScale, height: image.size.height * fitScale)

		setZoomScale(1, animated: false)
		minimumZoomScale = 1
		maximumZoomScale = 6
		imageView.frame = CGRect(origin: .zero, size: fittedSize)
		contentSize = fittedSize
		centerImage()
	}

	private func centerImage() {
		var frame = imageView.frame
		frame.origin.x = max((bounds.width - frame.width) / 2, 0)
		frame.origin.y = max((bounds.height - frame.height) / 2, 0)
		imageView.frame = frame
	}

	@objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
		if zoomScale > minimumZoomScale {
			setZoomScale(minimumZoomScale, animated: true)
			return
		}

		let targetScale = min(maximumZoomScale, 3)
		let point = recognizer.location(in: imageView)
		let zoomSize = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
		let zoomRect = CGRect(
			x: point.x - zoomSize.width / 2,
			y: point.y - zoomSize.height / 2,
			width: zoomSize.width,
			height: zoomSize.height
		)
		zoom(to: zoomRect, animated: true)
	}
}

#elseif canImport(AppKit)
import AppKit

struct ZoomablePlatformImage: View {
	var image: PlatformImage
	@State private var scale = 1.0

	var body: some View {
		GeometryReader { proxy in
			ScrollView([.horizontal, .vertical]) {
				Image(nsImage: image)
					.resizable()
					.scaledToFit()
					.scaleEffect(scale)
					.frame(width: proxy.size.width, height: proxy.size.height)
					.gesture(
						MagnifyGesture()
							.onChanged { value in
								scale = min(max(value.magnification, 1), 6)
							}
					)
			}
			.scrollIndicators(.hidden)
			.background(.black)
		}
	}
}
#endif
