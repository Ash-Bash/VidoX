import SwiftUI
import SwiftData

/// Browse pinned videos (TabView). On split view, pins also appear in the sidebar.
struct PinnedVideosView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Query(filter: #Predicate<DownloadedVideo> { $0.isPinned }, sort: \DownloadedVideo.pinnedAt, order: .reverse)
    private var pinnedVideos: [DownloadedVideo]

    @State private var selectedVideoID: UUID?

    var body: some View {
        Group {
            if pinnedVideos.isEmpty {
                EmptyStateView(
                    systemImage: "pin",
                    title: "No Pins Yet",
                    message: "Pin videos from the Library or Recent with the context menu or detail screen. Pinned items show up here and in the sidebar on larger devices.",
                    actionTitle: "Browse Library",
                    action: {
                        navigation.selectedDestination = .library
                        navigation.splitSelection = .destination(.library)
                    }
                )
            } else {
                List {
                    ForEach(pinnedVideos, id: \.id) { video in
                        Button {
                            selectedVideoID = video.id
                        } label: {
                            VideoRowView(video: video)
                        }
                        .buttonStyle(.plain)
                        .videoLibraryItemActions(
                            for: video,
                            onOpen: { selectedVideoID = video.id }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Pins")
        .navigationDestination(item: $selectedVideoID) { id in
            if let video = pinnedVideos.first(where: { $0.id == id }) {
                VideoDetailView(video: video)
            }
        }
        .toolbar { DetailDownloadToolbarItem() }
    }
}
