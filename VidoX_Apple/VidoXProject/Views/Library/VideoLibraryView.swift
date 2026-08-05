import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

/// Browse all downloaded videos — Photos-style grid with optional list layout.
/// Files stay in the app sandbox until the user explicitly exports them.
struct VideoLibraryView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \DownloadedVideo.downloadedAt, order: .reverse)
    private var videos: [DownloadedVideo]

    @AppStorage("library.layoutMode") private var layoutModeRaw = LibraryLayoutMode.grid.rawValue
    @State private var searchText = ""
    @State private var sortNewestFirst = true
    @State private var selectedVideoID: UUID?

    private var layoutMode: LibraryLayoutMode {
        get { LibraryLayoutMode(rawValue: layoutModeRaw) ?? .grid }
        nonmutating set { layoutModeRaw = newValue.rawValue }
    }

    private var filteredVideos: [DownloadedVideo] {
        let base: [DownloadedVideo]
        if searchText.isEmpty {
            base = videos
        } else {
            base = videos.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || ($0.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return sortNewestFirst
            ? base
            : base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 10)]
    }

    var body: some View {
        Group {
            if videos.isEmpty {
                EmptyStateView(
                    systemImage: "film.stack",
                    title: "Library Empty",
                    message: "Downloads stay inside VidoX. Use Save to Photos or Share / Files when you want a copy elsewhere.",
                    actionTitle: "Download a Video",
                    action: { navigation.isDownloaderPresented = true }
                )
            } else if filteredVideos.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                switch layoutMode {
                case .grid:
                    gridContent
                case .list:
                    listContent
                }
            }
        }
        .navigationTitle("Library")
        .navigationDestination(item: $selectedVideoID) { id in
            if let video = videos.first(where: { $0.id == id }) {
                VideoDetailView(video: video)
            }
        }
        .searchable(text: $searchText, prompt: "Search library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Plain toggle avoids the glitchy segmented control chrome on iOS toolbars.
                Button {
                    layoutMode = layoutMode == .grid ? .list : .grid
                } label: {
                    Image(systemName: layoutMode == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .help(layoutMode == .grid ? "Show as List" : "Show as Grid")
                .accessibilityLabel(layoutMode == .grid ? "Switch to list" : "Switch to grid")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(sortNewestFirst ? "Sort by Title" : "Sort by Newest") {
                        sortNewestFirst.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            DetailDownloadToolbarItem()
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(filteredVideos, id: \.id) { video in
                    Button {
                        selectedVideoID = video.id
                    } label: {
                        VideoGridItemView(video: video)
                    }
                    .buttonStyle(.plain)
                    .videoLibraryItemActions(
                        for: video,
                        onOpen: { selectedVideoID = video.id },
                        onDeleted: {
                            if selectedVideoID == video.id { selectedVideoID = nil }
                        }
                    )
                    #if os(macOS)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    #endif
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.02))
    }

    private var listContent: some View {
        List {
            ForEach(filteredVideos, id: \.id) { video in
                Button {
                    selectedVideoID = video.id
                } label: {
                    VideoRowView(video: video)
                }
                .buttonStyle(.plain)
                .videoLibraryItemActions(
                    for: video,
                    onOpen: { selectedVideoID = video.id },
                    onDeleted: {
                        if selectedVideoID == video.id { selectedVideoID = nil }
                    }
                )
            }
        }
        .listStyle(.plain)
    }
}
