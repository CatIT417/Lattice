import SwiftUI
import LinkPresentation

extension LPLinkMetadata: @unchecked @retroactive Sendable {}

#if canImport(UIKit)
struct LinkViewRepresentable: UIViewRepresentable {
	var metadata: LPLinkMetadata

	func makeUIView(context _: Context) -> LinkContainerView {
		LinkContainerView(metadata: metadata)
	}

	func updateUIView(_ view: LinkContainerView, context _: Context) {
		view.linkView.metadata = metadata
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView: LinkContainerView, context _: Context) -> CGSize? {
		let intrinsicWidth = uiView.linkView.intrinsicContentSize.width
		let proposedWidth = proposal.width ?? UIView.layoutFittingCompressedSize.width
		let width = intrinsicWidth > 0 ? min(proposedWidth, intrinsicWidth) : proposedWidth
		return uiView.systemLayoutSizeFitting(
			CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
			withHorizontalFittingPriority: .required,
			verticalFittingPriority: .fittingSizeLevel
		)
	}
}

/// Wraps `LPLinkView` and calls `invalidateIntrinsicContentSize()` when the link view
/// finishes loading its content, so SwiftUI re-queries `sizeThatFits`.
class LinkContainerView: UIView {
	let linkView: LPLinkView
	private var lastHeight: CGFloat = 0

	init(metadata: LPLinkMetadata) {
		linkView = LPLinkView(metadata: metadata)
		super.init(frame: .zero)

		addSubview(linkView)
		linkView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			linkView.topAnchor.constraint(equalTo: topAnchor),
			linkView.bottomAnchor.constraint(equalTo: bottomAnchor),
			linkView.leadingAnchor.constraint(equalTo: leadingAnchor),
			linkView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError()
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let newHeight = linkView.intrinsicContentSize.height
		if newHeight != lastHeight, newHeight > 0 {
			lastHeight = newHeight
			invalidateIntrinsicContentSize()
		}
	}

	override var intrinsicContentSize: CGSize {
		linkView.intrinsicContentSize
	}
}

#elseif canImport(AppKit)
struct LinkViewRepresentable: NSViewRepresentable {
	var metadata: LPLinkMetadata

	func makeNSView(context _: Context) -> LinkContainerView {
		LinkContainerView(metadata: metadata)
	}

	func updateNSView(_ view: LinkContainerView, context _: Context) {
		view.linkView.metadata = metadata
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkContainerView, context _: Context) -> CGSize? {
		let fittingSize = nsView.linkView.fittingSize
		let width = min(proposal.width ?? fittingSize.width, fittingSize.width)
		return CGSize(width: width, height: fittingSize.height)
	}
}

/// Wraps `LPLinkView` and calls `invalidateIntrinsicContentSize()` when the link view
/// finishes loading its content, so SwiftUI re-queries `sizeThatFits`.
class LinkContainerView: NSView {
	let linkView: LPLinkView
	private var lastHeight: CGFloat = 0

	init(metadata: LPLinkMetadata) {
		linkView = LPLinkView(metadata: metadata)
		super.init(frame: .zero)

		linkView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(linkView)
		NSLayoutConstraint.activate([
			linkView.topAnchor.constraint(equalTo: topAnchor),
			linkView.bottomAnchor.constraint(equalTo: bottomAnchor),
			linkView.leadingAnchor.constraint(equalTo: leadingAnchor),
			linkView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError()
	}

	override func layout() {
		super.layout()
		let newHeight = linkView.intrinsicContentSize.height
		if newHeight != lastHeight, newHeight > 0 {
			lastHeight = newHeight
			invalidateIntrinsicContentSize()
		}
	}

	override var intrinsicContentSize: NSSize {
		linkView.intrinsicContentSize
	}
}

#endif
