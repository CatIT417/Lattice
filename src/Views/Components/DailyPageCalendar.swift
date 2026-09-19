#if os(iOS)
import UIKit
import SwiftUI

struct DailyPageCalendar: UIViewRepresentable {
	let currentDay: DayOfYear
	var onSelect: (DayOfYear) -> Void

	@Environment(\.locale) private var locale

	func makeUIView(context: Context) -> UICalendarView {
		let view = UICalendarView()
		let calendar = Calendar(identifier: .gregorian, timezone: .autoupdatingCurrent)

		view.locale = locale
		view.calendar = calendar
		view.timeZone = calendar.timeZone
		view.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
		view.visibleDateComponents = calendar.dateComponents([.year, .month, .day], from: currentDay.date(in: calendar))

		return view
	}

	func updateUIView(_ view: UICalendarView, context: Context) {
		view.locale = locale
		context.coordinator.onSelect = onSelect
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context _: Context) -> CGSize? {
		uiView.systemLayoutSizeFitting(
			CGSize(
				width: proposal.width ?? uiView.intrinsicContentSize.width,
				height: UIView.layoutFittingCompressedSize.height
			),
			withHorizontalFittingPriority: .required,
			verticalFittingPriority: .fittingSizeLevel
		)
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(onSelect: onSelect)
	}

	final class Coordinator: NSObject, UICalendarSelectionSingleDateDelegate {
		var onSelect: (DayOfYear) -> Void

		init(onSelect: @escaping (DayOfYear) -> Void) {
			self.onSelect = onSelect
		}

		func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
			guard let dateComponents,
			      let day = dateComponents.day, let month = dateComponents.month, let year = dateComponents.year
			else { return }

			onSelect(DayOfYear(day: day, month: month, year: year))
			selection.setSelected(nil, animated: false)
		}
	}
}
#endif
