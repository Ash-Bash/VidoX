import SwiftUI
import AVFoundation
import AVKit

#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Persisted library presentation mode (Photos-style grid vs list).
enum LibraryLayoutMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }

    var label: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }
}

/// Loads a still frame from a local video file for library cells.
/// Sized by the parent — uses GeometryReader so `scaledToFill` cannot blow out the layout.
struct VideoThumbnailView: View {
    let url: URL
    var cornerRadius: CGFloat = 8

    @State private var image: Image?
    @State private var didFail = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))

                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else if didFail {
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .task(id: url.path) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        image = nil
        didFail = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            didFail = true
            return
        }

        guard let cgImage = await Self.generateCGImage(url: url) else {
            didFail = true
            return
        }

        #if os(iOS) || os(visionOS) || os(tvOS)
        image = Image(uiImage: UIImage(cgImage: cgImage))
        #elseif os(macOS)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        image = Image(nsImage: NSImage(cgImage: cgImage, size: size))
        #else
        image = Image(decorative: cgImage, scale: 1)
        #endif
    }

    private static func generateCGImage(url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        do {
            return try await generator.image(at: time).image
        } catch {
            return try? await generator.image(at: .zero).image
        }
    }
}

/// Compact Photos-style library tile — thumbnail on top, caption underneath.
struct VideoGridItemView: View {
    let video: DownloadedVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                VideoThumbnailView(url: video.fileURL, cornerRadius: 10)

                HStack(spacing: 4) {
                    if video.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.orange.opacity(0.9), in: Circle())
                    }
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .padding(6)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(video.platform.displayName) · \(video.formattedFileSize)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(video.title), \(video.formattedFileSize)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Full-window player sheet for a library video.
struct LibraryVideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView("Loading video…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .onAppear {
            PlaybackAudioSession.activateForPlayback()
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = false
            newPlayer.volume = 1
            player = newPlayer
            newPlayer.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
