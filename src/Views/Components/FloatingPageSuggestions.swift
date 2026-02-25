import SwiftUI

struct FloatingPageSuggestions: View {
	private enum ScrollTarget: Hashable {
		case top, row(Int)
	}

	private struct PanelPlacement {
		let x: CGFloat
		let y: CGFloat
		let width: CGFloat
	}

	private enum Metrics {
		static let minPanelWidth: CGFloat = 180
		static let maxPanelWidth: CGFloat = 320

		static let panelGap: CGFloat = 8
		static let verticalMargin: CGFloat = 8
		static let horizontalMargin: CGFloat = 8

		static let panelExtraHeight: CGFloat = 12

		static let maxListHeight: CGFloat = 220
		static let estimatedRowHeight: CGFloat = 36
		static let listVerticalPadding: CGFloat = 12
		static let estimatedPromptHeight: CGFloat = 44
	}

	let referenceSuggestions: ReferenceSuggestions

	@State private var scrollTarget: ScrollTarget?
	@State private var containerSize: CGSize = .zero
	@State private var measuredPanelHeight: CGFloat = 0
	@State private var topVisibleIndex: Int = 0

	private var minListHeight: CGFloat {
		min(
			Metrics.maxListHeight,
			(CGFloat(max(1, referenceSuggestions.suggestions.count)) * Metrics.estimatedRowHeight) + Metrics.listVerticalPadding
		)
	}

	private var estimatedVisibleRowCount: Int {
		max(1, Int((Metrics.maxListHeight - Metrics.listVerticalPadding) / Metrics.estimatedRowHeight))
	}

	private var panelHeight: CGFloat {
		guard measuredPanelHeight <= 0 else { return measuredPanelHeight }

		let estimatedPromptHeight = (referenceSuggestions.isQueryEmpty || referenceSuggestions.isQueryTooShort) ? Metrics.estimatedPromptHeight : 0
		let estimatedListHeight = referenceSuggestions.suggestions.count == 0 ? 0 : minListHeight

		return estimatedPromptHeight + estimatedListHeight + Metrics.panelExtraHeight
	}

	private var panelPlacement: PanelPlacement {
		let anchorRect = referenceSuggestions.anchorRect

		let aboveGap = max(0, anchorRect.minY - Metrics.panelGap)
		let belowGap = max(0, containerSize.height - anchorRect.maxY - Metrics.panelGap)
		let shouldPlaceAbove = panelHeight > belowGap && aboveGap > belowGap

		let width = clamp(
			containerSize.width - (Metrics.horizontalMargin * 2),
			to: Metrics.minPanelWidth...Metrics.maxPanelWidth
		)
		let maxX = max(Metrics.horizontalMargin, containerSize.width - width - Metrics.horizontalMargin)
		let maxY = max(Metrics.verticalMargin, containerSize.height - panelHeight - Metrics.verticalMargin)
		return PanelPlacement(
			x: clamp(anchorRect.minX, to: Metrics.horizontalMargin...maxX),
			y: clamp(
				shouldPlaceAbove
					? anchorRect.minY - panelHeight - Metrics.panelGap
					: anchorRect.maxY + Metrics.panelGap,
				to: Metrics.verticalMargin...maxY
			),
			width: width
		)
	}

	var body: some View {
		let placement = panelPlacement
		let suggestions = referenceSuggestions.suggestions

		VStack(alignment: .leading, spacing: 6) {
			if referenceSuggestions.isQueryEmpty || referenceSuggestions.isQueryTooShort {
				Text("Search for a Page")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding(.vertical, 8)
					.padding(.horizontal, 12)
			}

			if !suggestions.isEmpty {
				ScrollView(.vertical) {
					VStack(alignment: .leading, spacing: 0) {
						Color.clear
							.frame(height: 0)
							.id(ScrollTarget.top)

						VStack(alignment: .leading, spacing: 2) {
							ForEach(suggestions.indices, id: \.self) { index in
								let suggestion = suggestions[index]

								Button(action: { referenceSuggestions.acceptSuggestion(withTitle: suggestion.title) }) {
									HStack(spacing: 6) {
										Text(suggestion.title)
											.foregroundStyle(.primary)
											.lineLimit(1)

										if suggestion.isSyntheticNewPage {
											Text("(new page)")
												.foregroundStyle(.secondary)
												.lineLimit(1)
										}

										Spacer(minLength: 0)
									}
									.padding(.vertical, 8)
									.padding(.horizontal, 10)
									.frame(maxWidth: .infinity, alignment: .leading)
									.background(
										RoundedRectangle(cornerRadius: 10, style: .continuous)
											.fill(index == referenceSuggestions.highlightedIndex ? Color.accentColor.opacity(0.18) : .clear)
									)
								}
								.frame(maxWidth: .infinity, alignment: .leading)
								.id(ScrollTarget.row(index))
								.buttonStyle(.plain)
								#if os(macOS)
									.pointerStyle(.link)
								#else
									.hoverEffect()
								#endif
							}
						}
					}
					.scrollTargetLayout()
				}
				.padding(6)
				.frame(minHeight: minListHeight, maxHeight: Metrics.maxListHeight, alignment: .top)
				.scrollPosition(id: $scrollTarget, anchor: .top)
				.onAppear { synchronizeState(suggestionsCount: suggestions.count) }
				.onChange(of: suggestions) { _, newSuggestions in
					synchronizeState(suggestionsCount: newSuggestions.count)
				}
				.onChange(of: referenceSuggestions.shouldScrollToHighlighted) { _, shouldScroll in
					guard shouldScroll else { return }
					defer { referenceSuggestions.shouldScrollToHighlighted = false }

					scrollToHighlightedIfNeeded(suggestionsCount: suggestions.count)
				}
				.onScrollTargetVisibilityChange(idType: ScrollTarget.self, threshold: 0.01) { visibleTargets in
					updateTopVisibleIndex(visibleTargets, suggestionsCount: suggestions.count)
				}
			}
		}
		.frame(width: placement.width, alignment: .leading)
		.fixedSize(horizontal: false, vertical: true)
		.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { measuredPanelHeight = $0 }
		.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
		.offset(x: placement.x, y: placement.y)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.onGeometryChange(for: CGSize.self, of: { $0.size }) { containerSize = $0 }
	}

	private func topIndexToKeepHighlightedVisible(highlightedIndex: Int, currentTop: Int, totalCount: Int) -> Int {
		guard totalCount > 0 else { return 0 }

		let safeTop = clamp(currentTop, to: 0...(totalCount - 1))
		let safeHighlighted = clamp(highlightedIndex, to: 0...(totalCount - 1))
		let currentBottom = min(safeTop + estimatedVisibleRowCount - 1, totalCount - 1)

		if safeHighlighted < safeTop { return safeHighlighted }
		if safeHighlighted > currentBottom { return max(0, safeHighlighted - estimatedVisibleRowCount + 1) }
		return safeTop
	}

	private func synchronizeState(suggestionsCount: Int) {
		guard suggestionsCount > 0 else {
			scrollTarget = nil
			topVisibleIndex = 0
			return
		}

		let clampedIndex = clampedHighlightedIndex(referenceSuggestions.highlightedIndex, totalCount: suggestionsCount)
		if referenceSuggestions.highlightedIndex != clampedIndex {
			referenceSuggestions.highlightedIndex = clampedIndex
		}

		let clampedTopVisibleIndex = clampedHighlightedIndex(topVisibleIndex, totalCount: suggestionsCount)
		if topVisibleIndex != clampedTopVisibleIndex {
			topVisibleIndex = clampedTopVisibleIndex
		}

		let desiredTarget = scrollTarget(forTopIndex: scrollTarget == nil ? clampedIndex : clampedTopVisibleIndex)
		guard desiredTarget != scrollTarget else { return }

		setScrollTarget(desiredTarget)
	}

	private func scrollToHighlightedIfNeeded(suggestionsCount: Int) {
		guard suggestionsCount > 0 else { return }

		let highlightedIndex = clampedHighlightedIndex(
			referenceSuggestions.highlightedIndex,
			totalCount: suggestionsCount
		)
		if referenceSuggestions.highlightedIndex != highlightedIndex {
			referenceSuggestions.highlightedIndex = highlightedIndex
		}

		let currentTop = clampedHighlightedIndex(topVisibleIndex, totalCount: suggestionsCount)
		let targetTop = topIndexToKeepHighlightedVisible(
			highlightedIndex: highlightedIndex,
			currentTop: currentTop,
			totalCount: suggestionsCount
		)
		let desiredTarget = scrollTarget(forTopIndex: targetTop)
		guard desiredTarget != scrollTarget else { return }

		setScrollTarget(desiredTarget, animated: true)
	}

	private func updateTopVisibleIndex(_ visibleTargets: [ScrollTarget], suggestionsCount: Int) {
		guard suggestionsCount > 0 else {
			topVisibleIndex = 0
			return
		}

		let minimumVisibleRow = visibleTargets.compactMap { target in
			switch target {
				case .top: 0
				case let .row(index): index
			}
		}.min()

		guard let minimumVisibleRow else { return }
		topVisibleIndex = clamp(minimumVisibleRow, to: 0...(suggestionsCount - 1))
	}

	private func clampedHighlightedIndex(_ index: Int, totalCount: Int) -> Int {
		guard totalCount > 0 else { return 0 }
		return clamp(index, to: 0...(totalCount - 1))
	}

	private func scrollTarget(forTopIndex index: Int) -> ScrollTarget {
		index == 0 ? .top : .row(index)
	}

	private func setScrollTarget(_ target: ScrollTarget, animated: Bool = false) {
		switch target {
			case .top: topVisibleIndex = 0
			case let .row(index): topVisibleIndex = index
		}

		if animated {
			withAnimation(.easeOut(duration: 0.12)) {
				scrollTarget = target
			}
		} else {
			scrollTarget = target
		}
	}
}
