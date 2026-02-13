import SwiftUI

extension EnvironmentValues {
	/// The Block ID that should be considered the root for the current view hierarchy.
	///
	/// Note that this might not be the same as the main block of the page, like in `LinkedReferencesSection`.
	@Entry var rootBlockID: Block.ID?
}
