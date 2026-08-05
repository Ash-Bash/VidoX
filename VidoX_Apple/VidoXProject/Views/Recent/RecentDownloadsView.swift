import SwiftUI
import SwiftData

/// Chronological list of the most recent downloads (sandbox copies).
struct RecentDownloadsView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \DownloadedVideo.downloadedAt, order: .reverse)
    private var videos: [DownloadedVideo]

    private var recentVideos: [DownloadedVideo] {
        Array(videos.prefix(50))
    }

    var body: some View {
        Group {
            if recentVideos.isEmpty {
                EmptyStateView(
                    systemImage: "clock",
                    title: "No Recent Downloads",
                    message: "Videos you download stay in VidoX until you save them to Photos or Files.",
                    actionTitle: "Download a Video",
                    action: { navigation.isDownloaderPresented = true }
                )
            } else {
                List {
                    ForEach(recentVideos, id: \.id) { video in
                        NavigationLink {
                            VideoDetailView(video: video)
                        } label: {
                            VideoRowView(video: video)
                        }
                        .videoLibraryItemActions(for: video)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Recent")
        .toolbar { DetailDownloadToolbarItem() }
    }
}
