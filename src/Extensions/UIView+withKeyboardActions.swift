#if os(iOS)
import SwiftUI

@MainActor fileprivate var inputAccessoryViewControllerKey: Void?

public extension UIView {
	override var inputAccessoryViewController: UIInputViewController? {
		get { objc_getAssociatedObject(self, &inputAccessoryViewControllerKey) as? UIInputViewController }
		set { objc_setAssociatedObject(self, &inputAccessoryViewControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
	}

	func withKeyboardActions(items: [UIBarButtonItem]) {
		inputAccessoryViewController = KeyboardToolbarController(items: items)
	}
}

class KeyboardToolbarController: UIInputViewController {
	let items: [UIBarButtonItem]

	init(items: [UIBarButtonItem]) {
		self.items = items
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let toolbar = UIToolbar()
		toolbar.items = items
		toolbar.sizeToFit()

		view.addSubview(toolbar)

		toolbar.translatesAutoresizingMaskIntoConstraints = false

		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
			toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
		])
	}
}
#endif
