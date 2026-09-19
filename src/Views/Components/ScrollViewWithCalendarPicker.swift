import SwiftUI

struct ScrollViewWithCalendarPicker<Content: View>: View {
	let currentDay: DayOfYear
	let onSelectDate: (DayOfYear, () -> Void) -> Void
	@ViewBuilder let content: Content

	#if os(iOS)
	@State private var canRevealCalendar = false
	@State private var viewportHeight: CGFloat = 0
	@State private var calendarPullDistance: CGFloat = 0
	@State private var isResettingScrollPosition = false
	@State private var calendarScroll = DailyPageCalendarScrollBehavior()
	@State private var scrollPosition = ScrollPosition(idType: String.self)

	private var calendarRevealDistance: CGFloat {
		canRevealCalendar ? min(calendarScroll.height, calendarPullDistance * 2.5) : 0
	}
	#endif

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				#if os(iOS)
				// Keep the first note at scroll offset zero while the calendar is closed.
				Color.clear
					.frame(height: calendarScroll.isPresented ? calendarScroll.height : 0)
					.overlay(alignment: .bottom) {
						DailyPageCalendar(currentDay: currentDay, onSelect: selectDate)
							.fixedSize(horizontal: false, vertical: true)
							.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { calendarScroll.height = $0 }
							.frame(height: calendarScroll.isPresented ? calendarScroll.height : calendarRevealDistance, alignment: .bottom)
							.clipped()
							.allowsHitTesting(calendarScroll.isPresented)
							.accessibilityHidden(!calendarScroll.isPresented)
					}
				#endif

				content
					.id("daily-pages")
					#if os(iOS)
					// Keep native text views with their notes while the calendar moves them.
					.geometryGroup()
					.frame(minHeight: viewportHeight, maxHeight: calendarScroll.isPresented || isResettingScrollPosition ? viewportHeight : nil, alignment: .top)
					.unfocusBlockOnBackgroundTap()
					.clipped()
					#endif
			}
			.scrollTargetLayout()
			#if os(iOS)
			// Reduce the resistance of the pull without changing the active scroll gesture.
			.offset(y: calendarScroll.isPresented ? 0 : max(0, calendarRevealDistance - calendarPullDistance))
			#endif
		}
		#if os(iOS)
		.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewportHeight = $0 }
		.scrollPosition($scrollPosition)
		.scrollTargetBehavior(calendarScroll)
		.scrollDismissesKeyboard(.interactively)
		.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, offset in
			calendarPullDistance = max(0, -offset)
			if isResettingScrollPosition, abs(offset) < 1 {
				isResettingScrollPosition = false
			}
			if calendarScroll.isPresented, !calendarScroll.isInteracting, abs(offset - calendarScroll.height) <= 2 {
				hideCalendar()
			}
		}
		.onScrollPhaseChange { oldPhase, newPhase, context in
			let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top

			// A gesture must start at the top to reveal the calendar.
			if newPhase == .tracking || (newPhase == .interacting && oldPhase != .tracking) {
				canRevealCalendar = offset <= 1
			}

			calendarScroll.isInteracting = newPhase == .interacting || newPhase == .tracking
			if newPhase == .interacting { calendarScroll.snapOffset = nil }

			if oldPhase == .interacting, !calendarScroll.isPresented, canRevealCalendar, offset < -60 {
				showCalendar()
			} else if calendarScroll.isPresented, !calendarScroll.isInteracting, abs(offset - calendarScroll.height) <= 2 {
				hideCalendar()
			} else if oldPhase == .interacting, newPhase != .animating, calendarScroll.isPresented, let snapOffset = calendarScroll.snapOffset {
				withAnimation(.snappy(duration: 0.35)) {
					scrollPosition.scrollTo(y: snapOffset)
				}
			}
		}
		.accessibilityAction(named: Text("Choose Date"), showCalendar)
		#else
		.unfocusBlockOnBackgroundTap()
		#endif
	}

	#if os(iOS)
	private func hideCalendar() {
		var transaction = Transaction()
		transaction.disablesAnimations = true
		transaction.scrollContentOffsetAdjustmentBehavior = .disabled
		withTransaction(transaction) {
			// Keep the feed within the viewport until the scroll position is at the top.
			isResettingScrollPosition = true
			calendarScroll.isPresented = false
			scrollPosition.scrollTo(y: 0)
		}
	}

	private func showCalendar() {
		UIApplication.shared.dismissKeyboard()
		withAnimation(.snappy(duration: 0.35)) {
			calendarScroll.isPresented = true
			scrollPosition.scrollTo(edge: .top)
		}
	}

	private func selectDate(_ day: DayOfYear) {
		onSelectDate(day) {
			calendarScroll.isPresented = false
			scrollPosition.scrollTo(edge: .top)
		}
	}
	#endif
}

#if os(iOS)
@Observable
private final class DailyPageCalendarScrollBehavior: ScrollTargetBehavior {
	var height: CGFloat = 0
	var isPresented = false
	@ObservationIgnored var isInteracting = false
	/// Use the projected target for the release animation.
	@ObservationIgnored var snapOffset: CGFloat?

	func updateTarget(_ target: inout ScrollTarget, context _: TargetContext) {
		snapOffset = nil
		guard isPresented else { return }

		target.anchor = .top
		snapOffset = target.rect.minY
		target.rect.origin.y = target.rect.minY < height / 2 ? 0 : height
	}
}
#endif
