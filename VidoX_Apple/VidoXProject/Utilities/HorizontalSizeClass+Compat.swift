import SwiftUI

extension View {
    /// Chooses TabView vs SplitView. Mac and visionOS always use the regular shell;
    /// iPhone / iPad follow `horizontalSizeClass` (compact → tabs).
    @ViewBuilder
    func adaptiveRootShell<Compact: View, Regular: View>(
        sizeClass: UserInterfaceSizeClass?,
        @ViewBuilder compact: () -> Compact,
        @ViewBuilder regular: () -> Regular
    ) -> some View {
        #if os(macOS) || os(visionOS)
        regular()
        #else
        if sizeClass == .compact {
            compact()
        } else {
            regular()
        }
        #endif
    }
}
