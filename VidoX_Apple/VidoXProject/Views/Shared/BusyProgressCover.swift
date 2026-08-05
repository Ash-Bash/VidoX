import SwiftUI

/// Compact centered busy HUD — spinner + status, no oversized panel.
struct BusyProgressCover: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    /// Presents busy progress centered in the window — not clipped to a grid cell.
    /// Uses `fullScreenCover` on iOS/visionOS; fitted `sheet` on macOS.
    func busyProgressCover(isPresented: Binding<Bool>, label: String) -> some View {
        #if os(macOS)
        self.sheet(isPresented: isPresented) {
            BusyProgressCover(label: label)
                .padding(20)
                .interactiveDismissDisabled()
                .presentationSizing(.fitted)
                .presentationBackground(.clear)
        }
        #else
        self.fullScreenCover(isPresented: isPresented) {
            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                BusyProgressCover(label: label)
            }
            .presentationBackground(.clear)
            .interactiveDismissDisabled()
        }
        #endif
    }
}
