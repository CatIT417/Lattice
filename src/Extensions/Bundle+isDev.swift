import Foundation

extension Bundle {
	var isDev: Bool {
		bundleIdentifier!.hasSuffix(".dev")
	}
}
