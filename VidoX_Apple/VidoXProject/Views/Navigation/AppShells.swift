import SwiftUI
import SwiftData

/// iPhone / compact-width shell using tabs — Pins is its own tab.
struct CompactTabShell: View {
    @Environment(AppNavigationState.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedDestination) {
            NavigationStack {
                VideoLibraryView()
                    .toolbar { nearbySyncToolbarItem }
            }
            .tabItem { Label(AppDestination.library.title, systemImage: AppDestination.library.systemImage) }
            .tag(AppDestination.library)

            NavigationStack {
                PinnedVideosView()
                    .toolbar { nearbySyncToolbarItem }
            }
            .tabItem { Label(AppDestination.pins.title, systemImage: AppDestination.pins.systemImage) }
            .tag(AppDestination.pins)

            NavigationStack {
                SettingsView()
                    .toolbar { nearbySyncToolbarItem }
            }
            .tabItem { Label(AppDestination.settings.title, systemImage: AppDestination.settings.systemImage) }
            .tag(AppDestination.settings)
        }
        .environment(\.showsDetailDownloadButton, true)
    }

    @ToolbarContentBuilder
    private var nearbySyncToolbarItem: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            NearbySyncCompactButton()
        }
        #else
        ToolbarItem(placement: .topBarLeading) {
            NearbySyncCompactButton()
        }
        #endif
    }
}

/// iPad / Mac / visionOS shell — browse destinations plus a Pinned sidebar section.
struct RegularSplitShell: View {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @Query private var allVideos: [DownloadedVideo]
    @Query(filter: #Predicate<DownloadedVideo> { $0.isPinned }, sort: \DownloadedVideo.pinnedAt, order: .reverse)
    private var pinnedVideos: [DownloadedVideo]

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    sidebarActionCard(
                        .library,
                        count: allVideos.count
                    )
                    sidebarActionCard(.settings)
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 6)

                List(selection: pinnedSidebarSelection) {
                    Section {
                        if pinnedVideos.isEmpty {
                            Text("Pin videos from Library")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pinnedVideos, id: \.id) { video in
                                HStack(spacing: 10) {
                                    VideoThumbnailView(url: video.fileURL, cornerRadius: 6)
                                        .frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(video.title)
                                            .lineLimit(1)
                                        Text(video.platform.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(SplitSidebarSelection.pinnedVideo(video.id))
                                .contextMenu {
                                    Button {
                                        let id = video.id
                                        video.togglePinned()
                                        try? modelContext.save()
                                        if case .pinnedVideo(let selected) = navigation.splitSelection, selected == id {
                                            navigation.splitSelection = .destination(.library)
                                        }
                                    } label: {
                                        Label("Unpin", systemImage: "pin.slash")
                                    }
                                }
                            }
                        }
                    } header: {
                        Label("Pinned", systemImage: "pin.fill")
                    }
                }
                .listStyle(.sidebar)
                #if os(iOS) || os(visionOS)
                .listSectionSpacing(8)
                #endif
            }
            .navigationTitle("VidoX")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DownloadToolbarButton()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NearbySyncSidebarFooter()
            }
        } detail: {
            NavigationStack {
                detailContent
            }
            .environment(\.showsDetailDownloadButton, false)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: navigation.splitSelection) { _, newValue in
            if case .destination(let destination) = newValue {
                navigation.selectedDestination = destination
            }
        }
    }

    /// List selection only tracks pinned rows — browse cards set destination themselves.
    private var pinnedSidebarSelection: Binding<SplitSidebarSelection?> {
        Binding(
            get: {
                if case .pinnedVideo = navigation.splitSelection {
                    navigation.splitSelection
                } else {
                    nil
                }
            },
            set: { newValue in
                if let newValue {
                    navigation.splitSelection = newValue
                }
            }
        )
    }

    private func sidebarActionCard(_ destination: AppDestination, count: Int? = nil) -> some View {
        let selected = navigation.splitSelection == .destination(destination)
        return Button {
            navigation.go(to: destination)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: destination.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(destination.accentColor, in: Circle())
                    Spacer(minLength: 2)
                    if let count {
                        Text("\(count)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(destination.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                selected
                    ? Color.accentColor.opacity(0.22)
                    : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var detailContent: some View {
        switch navigation.splitSelection {
        case .destination(.library):
            VideoLibraryView()
        case .destination(.pins):
            PinnedVideosView()
        case .destination(.settings):
            SettingsView()
        case .pinnedVideo(let id):
            if let video = pinnedVideos.first(where: { $0.id == id }) {
                VideoDetailView(video: video)
            } else {
                ContentUnavailableView(
                    "Pin Removed",
                    systemImage: "pin.slash",
                    description: Text("This video is no longer pinned.")
                )
            }
        case .none:
            ContentUnavailableView(
                "VidoX",
                systemImage: "arrow.down.circle",
                description: Text("Choose Library or a pinned video.")
            )
        }
    }
}
