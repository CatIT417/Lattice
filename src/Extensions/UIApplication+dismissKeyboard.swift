import UIKit

extension UIApplication {
	func resignFirstResponder() {
		sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
	}
}
