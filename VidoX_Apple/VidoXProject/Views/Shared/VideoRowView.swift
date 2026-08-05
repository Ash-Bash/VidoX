import SwiftUI

struct VideoRowView: View {
    let video: DownloadedVideo

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                VideoThumbnailView(url: video.fileURL, cornerRadius: 8)
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(4)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if video.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(video.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    Text(video.platform.displayName)
                    Text("·")
                    Text(video.downloadedAt, style: .relative)
                    Text("·")
                    Text(video.formattedFileSize)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
