import SwiftUI

/// Shared progress content used by sidebar footer and compact popover.
struct NearbySyncProgressContent: View {
    @Environment(LocalSyncService.self) private var sync

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.accentColor)
                Text("Nearby Sync")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if sync.activeTransferCount > 0 {
                    Text("\(sync.activeTransferCount)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(sync.transferDetail.isEmpty ? sync.statusText : sync.transferDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let fraction = sync.transferFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                Text("\(Int(fraction * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if let peer = sync.connectedPeerName {
                Text("With \(peer)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bottom-of-sidebar transfer strip for regular width (iPad / Mac / visionOS).
struct NearbySyncSidebarFooter: View {
    @Environment(LocalSyncService.self) private var sync

    var body: some View {
        Group {
            if sync.hasTransferActivity {
                NearbySyncProgressContent()
                    .padding(12)
                    .background(.bar)
                    .overlay(alignment: .top) {
                        Divider()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sync.hasTransferActivity)
        .animation(.easeInOut(duration: 0.2), value: sync.transferFraction)
    }
}

/// Floating control for compact width — tap for a progress popover; hidden when idle.
struct NearbySyncCompactButton: View {
    @Environment(LocalSyncService.self) private var sync
    @State private var showPopover = false

    var body: some View {
        Group {
            if sync.hasTransferActivity {
                Button {
                    showPopover = true
                } label: {
                    ZStack {
                        if let fraction = sync.transferFraction {
                            Circle()
                                .trim(from: 0, to: max(fraction, 0.02))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 22, height: 22)
                        }

                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .accessibilityLabel("Nearby sync progress")
                .help("Nearby sync progress")
                .popover(isPresented: $showPopover, arrowEdge: .top) {
                    NearbySyncProgressContent()
                        .padding(16)
                        .frame(minWidth: 260)
                        .presentationCompactAdaptation(.popover)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sync.hasTransferActivity)
        .onChange(of: sync.hasTransferActivity) { _, active in
            if !active {
                showPopover = false
            }
        }
    }
}
