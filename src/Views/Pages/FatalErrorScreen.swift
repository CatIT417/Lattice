import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FatalErrorScreen: View {
	var error: any Error
	@State private var didCopyDiagnostics = false

	private var errorSummary: String {
		let localizedDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
		let rawDescription = String(describing: error).trimmingCharacters(in: .whitespacesAndNewlines)

		guard !localizedDescription.isEmpty else { return rawDescription }
		guard localizedDescription != rawDescription, !rawDescription.isEmpty else { return localizedDescription }

		return "\(localizedDescription)\n\n\(rawDescription)"
	}

	private var osVersion: String {
		let version = ProcessInfo.processInfo.operatingSystemVersion

		#if os(macOS)
		return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
		#else
		return "iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
		#endif
	}

	private var appVersion: String {
		let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
		let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

		return "\(shortVersion) (\(buildNumber))"
	}

	private var diagnostics: String {
		[
			"Error: \(errorSummary)",
			"App version: \(appVersion)",
			"OS: \(osVersion)",
			"Timestamp: \(ISO8601DateFormatter().string(from: Date.now))",
		].joined(separator: "\n")
	}

	var body: some View {
		VStack(spacing: 24) {
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.system(size: 64))
				.foregroundStyle(.yellow)

			VStack(spacing: 8) {
				Text("Unable to Start")
					.font(.title.bold())

				Text(error.localizedDescription)
					.font(.body)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}

			VStack(alignment: .leading, spacing: 12) {
				Label("Diagnostics", systemImage: "terminal")
					.font(.headline)
					.foregroundStyle(.secondary)

				Text(diagnostics)
					.font(.system(.footnote, design: .monospaced))
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.padding(16)
			.background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

			Button(action: copyDiagnostics) {
				Image(systemName: didCopyDiagnostics ? "checkmark.circle.fill" : "doc.on.doc")
					.contentTransition(.symbolEffect)

				Text(didCopyDiagnostics ? "Copied to clipboard" : "Copy diagnostics")
					.contentTransition(.numericText(countsDown: !didCopyDiagnostics))
			}
			.buttonStyle(.glassProminent)
			.animation(.default, value: didCopyDiagnostics)
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
	}

	private func copyDiagnostics() {
		copyToClipboard(diagnostics)

		didCopyDiagnostics = true
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
			didCopyDiagnostics = false
		}
	}
}

// MARK: - Preview

fileprivate enum MockError: LocalizedError {
	case example

	var errorDescription: String? {
		"The database could not be created because startup migrations failed."
	}
}

#Preview {
	FatalErrorScreen(error: MockError.example)
}
