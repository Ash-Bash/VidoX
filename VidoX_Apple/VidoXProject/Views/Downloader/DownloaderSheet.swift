import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Modal flow: paste URL → extract metadata → pick format → download.
struct DownloaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = DownloaderViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    urlCard
                    if viewModel.isExtracting {
                        loadingCard
                    }
                    if let error = viewModel.errorMessage {
                        errorCard(error)
                    }
                    if let metadata = viewModel.metadata {
                        metadataCard(metadata)
                        if metadata.allowsRealDownload {
                            formatCard(metadata)
                            if metadata.usesYTDLP {
                                experimentalBanner
                            }
                        } else {
                            socialUnavailableCard(metadata)
                        }
                        if viewModel.isDownloading {
                            progressCard
                        }
                    } else if !viewModel.isExtracting && viewModel.errorMessage == nil {
                        tipCard
                    }
                }
                .padding(20)
            }
            .background(Color.primary.opacity(0.03))
            .navigationTitle("Download")
            .modifier(InlineNavTitleModifier())
            #if os(iOS) || os(visionOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
            .safeAreaInset(edge: .bottom) {
                footerBar
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520, idealHeight: 580)
        #endif
    }

    // MARK: - Cards

    private var urlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video link")
                .font(.headline)

            URLInputView(urlText: $viewModel.urlText)

            Button {
                Task { await viewModel.fetchMetadata() }
            } label: {
                HStack {
                    if viewModel.isExtracting {
                        ProgressView()
                            .controlSize(.small)
                    }
            Text(viewModel.isExtracting ? "Looking up…" : "Fetch Info")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isExtracting)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Looking up video…")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "xmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metadataCard(_ metadata: VideoMetadata) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                thumbnailView(for: metadata)

                VStack(alignment: .leading, spacing: 6) {
                    Text(metadata.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                    if let author = metadata.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    PlatformBadge(platform: metadata.platform)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func thumbnailView(for metadata: VideoMetadata) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let thumb = metadata.thumbnailURL {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        platformPlaceholder(metadata.platform)
                    default:
                        ProgressView()
                    }
                }
            } else {
                platformPlaceholder(metadata.platform)
            }
        }
        .frame(width: 96, height: 72)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
    }

    private func platformPlaceholder(_ platform: VideoPlatform) -> some View {
        ZStack {
            platform.accentColor.opacity(0.18)
            Image(systemName: platform.iconName)
                .font(.title2)
                .foregroundStyle(platform.accentColor)
        }
    }

    private func formatCard(_ metadata: VideoMetadata) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality")
                .font(.headline)
            FormatPickerView(
                formats: metadata.formats,
                selection: $viewModel.selectedFormatID,
                recommendedID: metadata.bestVideoFormat?.id
            )
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var experimentalBanner: some View {
        Label(
            "Standalone downloads are on. On iPhone, media URLs are resolved in-app; on Mac a download engine is fetched on first use. Turn off FeatureFlags.experimentalSocialDownloads for App Store builds.",
            systemImage: "hammer.fill"
        )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func socialUnavailableCard(_ metadata: VideoMetadata) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Download not available yet", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("\(metadata.platform.displayName) links can be recognized, but downloading from social platforms isn’t enabled while VidoX stays App Store–ready. Use a direct media file URL instead (ends in .mp4, .mov, and similar).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Downloading")
                .font(.headline)
            if let fraction = viewModel.progressFraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text(viewModel.progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How downloads work", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
            if FeatureFlags.experimentalSocialDownloads {
                Text("Standalone mode: paste a video page (YouTube, Vimeo, …) or a direct .mp4 link. On iPhone the app resolves media URLs itself; on Mac it uses a built-in engine fetched on first use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Paste a direct link to a video file (for example …/clip.mp4). Video pages are preview-only in this App Store–ready mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            #if os(macOS)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            #endif

            Button {
                Task {
                    let saved = await viewModel.startDownload(modelContext: modelContext)
                    if saved { dismiss() }
                }
            } label: {
                if viewModel.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    iconAndTitle("Download", systemImage: "arrow.down")
                }
            }
            .labelsVisibility(.visible)
            .disabled(!viewModel.canDownload)
            .tint(viewModel.canDownload ? Color.accentColor : Color.primary)
            .keyboardShortcut(.defaultAction)
            #if os(iOS) || os(visionOS)
            .frame(maxWidth: .infinity)
            #endif
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

@ViewBuilder
private func iconAndTitle(_ title: String, systemImage: String) -> some View {
    // HStack, not Label — iPhone toolbars collapse Label to icon-only even with titleAndIcon.
    HStack(spacing: 6) {
        Image(systemName: systemImage)
        Text(title)
    }
}

struct URLInputView: View {
    @Binding var urlText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)

            // Avoid Form-style title rendering; prompt-only field fixes the macOS “https://…” ghost label.
            TextField("", text: $urlText, prompt: Text("https://… video page or .mp4"))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                #endif
                #if os(macOS)
                .textFieldStyle(.plain)
                #endif

            Button {
                pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help("Paste from clipboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func pasteFromClipboard() {
        #if os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            urlText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #else
        if let string = UIPasteboard.general.string {
            urlText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }
}

struct FormatPickerView: View {
    let formats: [VideoFormat]
    @Binding var selection: String?
    var recommendedID: String? = nil

    var body: some View {
        let video = formats.filter { !$0.isAudioOnly }
        let audio = formats.filter(\.isAudioOnly)
        VStack(spacing: 8) {
            ForEach(video) { format in
                formatRow(format, badge: format.id == recommendedID ? "Recommended" : nil)
            }
            if !audio.isEmpty, !video.isEmpty {
                Text("Audio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            ForEach(audio) { format in
                formatRow(format, badge: "Audio")
            }
        }
    }

    private func formatRow(_ format: VideoFormat, badge: String?) -> some View {
        Button {
            selection = format.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selection == format.id ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selection == format.id ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(format.qualityTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(format.formatDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(format.id == recommendedID ? Color.accentColor : .secondary)
                        .background(
                            (format.id == recommendedID ? Color.accentColor : Color.secondary)
                                .opacity(0.14),
                            in: Capsule()
                        )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selection == format.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Owns extraction + download state for the downloader sheet.
@Observable
@MainActor
final class DownloaderViewModel {
    var urlText = ""
    var metadata: VideoMetadata?
    var selectedFormatID: String?
    var isExtracting = false
    var isDownloading = false
    var progressFraction: Double?
    var progressLabel = ""
    var errorMessage: String?

    private let urlDownloader: any VideoDownloading = URLSessionVideoDownloader()
    #if os(macOS)
    private let ytdlpDownloader = YTDLPVideoDownloader()
    #endif

    var canDownload: Bool {
        guard let metadata, metadata.allowsRealDownload, !isDownloading, !isExtracting else {
            return false
        }
        return selectedFormat != nil
    }

    private var selectedFormat: VideoFormat? {
        guard let metadata, let selectedFormatID else { return nil }
        return metadata.formats.first { $0.id == selectedFormatID }
    }

    func fetchMetadata() async {
        errorMessage = nil
        metadata = nil
        selectedFormatID = nil
        progressFraction = nil

        guard let url = URLNormalizer.url(from: urlText) else {
            errorMessage = ExtractionError.invalidURL.localizedDescription
            return
        }

        // Keep the field tidy after a successful parse.
        urlText = url.absoluteString
        isExtracting = true
        defer { isExtracting = false }

        do {
            let captured = url
            let result = try await withThrowingTaskGroup(of: VideoMetadata.self) { group in
                defer { group.cancelAll() }
                group.addTask {
                    try await ExtractionRouter().extract(from: captured)
                }
                group.addTask {
                    // Some hosts (Facebook share links, Reddit, Twitch GQL) need extra headroom.
                    let platform = VideoPlatform.detect(from: captured.absoluteString)
                    let seconds: Double = {
                        switch platform {
                        case .facebook, .reddit, .twitch, .twitter: 28
                        case .instagram, .tiktok, .rumble: 22
                        case .youtube: 12
                        default: 15
                        }
                    }()
                    try await Task.sleep(for: .seconds(seconds))
                    throw PageExtractionError.network(
                        "Timed out looking up this video. Check your connection and try again."
                    )
                }
                // next() throwing used to leave yt-dlp running, so the spinner never stopped.
                while let outcome = await group.nextResult() {
                    switch outcome {
                    case .success(let metadata):
                        return metadata
                    case .failure(let error):
                        if error is CancellationError { continue }
                        throw error
                    }
                }
                throw PageExtractionError.network("Couldn’t look up this video.")
            }
            metadata = result
            selectedFormatID = result.bestVideoFormat?.id ?? result.formats.first?.id
        } catch is CancellationError {
            errorMessage = "Lookup cancelled."
        } catch {
            errorMessage = TransferErrorHelp.userFacingMessage(from: error)
        }
    }

    /// Returns `true` when a library record was saved successfully.
    func startDownload(modelContext: ModelContext) async -> Bool {
        guard let metadata, metadata.allowsRealDownload, let format = selectedFormat else {
            return false
        }

        errorMessage = nil
        isDownloading = true
        progressFraction = nil
        progressLabel = metadata.usesYTDLP ? "Preparing…" : "Starting…"
        defer { isDownloading = false }

        var destination = FileStorage.makeVideoFileURL(
            preferredName: metadata.title,
            fileExtension: format.fileExtension
        )

        do {
            #if os(macOS)
            if metadata.platform == .youtube || (metadata.usesYTDLP && format.ytdlpFormatSelector != nil) {
                let selector = format.ytdlpFormatSelector
                    ?? ExperimentalSocialExtractor.youtubeFormatSelector
                for try await progress in ytdlpDownloader.download(
                    pageURL: metadata.sourceURL,
                    formatSelector: selector,
                    to: destination
                ) {
                    progressFraction = progress.fraction
                    progressLabel = progress.totalBytes == nil
                        ? "Downloading…"
                        : "Finished"
                }
                // Resolve the file yt-dlp actually wrote (extension may differ).
                let directory = destination.deletingLastPathComponent()
                let stem = destination.deletingPathExtension().lastPathComponent
                if let match = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter({ $0.lastPathComponent.hasPrefix(stem) })
                    .sorted(by: { $0.lastPathComponent.count < $1.lastPathComponent.count })
                    .first {
                    destination = match
                }
            } else if format.isHLSStream {
                progressLabel = "Exporting stream…"
                progressFraction = nil
                let exportDestination = destination.deletingPathExtension().appendingPathExtension("mp4")
                try await HLSVideoDownloader.download(from: format.url, to: exportDestination)
                destination = exportDestination
                progressLabel = "Finished"
                progressFraction = 1
            } else {
                try await runURLSessionDownload(from: format.url, to: destination)
            }
            #else
            // Direct/Piped URLs via URLSession; HLS via AVFoundation export.
            if format.isHLSStream {
                progressLabel = "Exporting stream…"
                progressFraction = nil
                let exportDestination = destination.deletingPathExtension().appendingPathExtension("mp4")
                try await HLSVideoDownloader.download(from: format.url, to: exportDestination)
                destination = exportDestination
                progressLabel = "Finished"
                progressFraction = 1
            } else {
                try await runURLSessionDownload(from: format.url, to: destination)
            }
            #endif

            let size = FileStorage.fileSize(at: destination)
            let record = DownloadedVideo(
                title: metadata.title,
                author: metadata.author,
                sourceURL: metadata.sourceURL.absoluteString,
                platform: metadata.platform,
                localFilePath: FileStorage.storedPath(for: destination),
                fileExtension: destination.pathExtension.isEmpty ? format.fileExtension : destination.pathExtension,
                fileSize: size
            )
            modelContext.insert(record)
            try modelContext.save()
            LocalSyncService.shared.noteUpserted(videoID: record.id)
            return true
        } catch {
            FileStorage.removeFile(at: destination.path)
            if let downloadError = error as? DownloadError, case .cancelled = downloadError {
                errorMessage = nil
            } else {
                errorMessage = TransferErrorHelp.userFacingMessage(from: error)
            }
            return false
        }
    }

    private func runURLSessionDownload(from remoteURL: URL, to destination: URL) async throws {
        for try await progress in urlDownloader.download(from: remoteURL, to: destination) {
            progressFraction = progress.fraction
            if let total = progress.totalBytes {
                let received = ByteCountFormatter.string(fromByteCount: progress.bytesReceived, countStyle: .file)
                let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                progressLabel = "\(received) of \(totalText)"
            } else {
                let received = ByteCountFormatter.string(fromByteCount: progress.bytesReceived, countStyle: .file)
                progressLabel = "\(received) downloaded"
            }
        }
    }
}

private struct InlineNavTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
        content.navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}
