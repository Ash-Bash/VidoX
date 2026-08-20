import Foundation

enum DownloadError: LocalizedError, Sendable {
    case cancelled
    case invalidResponse
    case httpStatus(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Download cancelled."
        case .invalidResponse:
            "The site sent a response VidoX couldn’t use. Try the link again."
        case .httpStatus(let code):
            TransferErrorHelp.message(forHTTPStatus: code)
        case .writeFailed(let message):
            "Could not save the file: \(message)"
        }
    }
}

/// Plain-language explanations for HTTP / downloader failures.
enum TransferErrorHelp {
    static func message(forHTTPStatus code: Int) -> String {
        switch code {
        case 400:
            "The site didn’t understand that request (400). Copy the link again and retry."
        case 401:
            "This video needs a sign-in (401). Private or members-only videos can’t be downloaded here."
        case 403:
            "The site blocked this download (403). That usually means this file isn’t allowed to be saved — on YouTube the standard video file is often restricted. Try again, pick another quality, or use a different video. Age-restricted and some music videos also do this."
        case 404:
            "Nothing was found at that link (404). The video may have been deleted, or the URL is incomplete."
        case 408:
            "The site took too long to respond (408). Check your connection and try again."
        case 410:
            "This video is gone (410). It was removed from the site."
        case 416:
            "The download couldn’t resume (416). Start it again from the beginning."
        case 429:
            "Too many requests (429). Wait a minute, then try again."
        case 451:
            "This video isn’t available in your region (451)."
        case 500, 502, 503, 504:
            "The site had a temporary problem (\(code)). Try again in a moment."
        default:
            if (500..<600).contains(code) {
                "The site had a server problem (\(code)). Try again in a moment."
            } else {
                "Download failed (HTTP \(code)). The site refused the request."
            }
        }
    }

    static func httpStatus(in text: String) -> Int? {
        let patterns = [
            "HTTP Error ([0-9]{3})",
            "status(?: code)?[: ]+([0-9]{3})",
            "HTTP/\\d(?:\\.\\d)? ([0-9]{3})",
            "\\bHTTP(?: status)?[: ]+([0-9]{3})",
            "\\(([0-9]{3})\\)"
        ]
        for pattern in patterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let snippet = String(text[match])
                let digits = snippet.filter(\.isNumber)
                if let code = Int(digits), (400..<600).contains(code) {
                    return code
                }
            }
        }
        return nil
    }

    static func userFacingMessage(from error: Error) -> String {
        if let download = error as? DownloadError {
            return download.errorDescription ?? "Download failed."
        }
        let text = error.localizedDescription
        if let code = httpStatus(in: text) {
            return message(forHTTPStatus: code)
        }
        let lower = text.lowercased()
        if lower.contains("requested format is not available") || lower.contains("list-formats") {
            return "YouTube didn’t offer a matching file for that quality. Try Fetch Info again, or pick another quality."
        }
        if lower.contains("page needs to be reloaded") {
            return "YouTube asked the player to reload. Try Fetch Info again — this is a temporary YouTube block."
        }
        if lower.contains("sign in to confirm") || lower.contains("not a bot") {
            return "YouTube is asking for a sign-in to confirm this isn’t automated. Try again in a moment, or use a different video."
        }
        if lower.contains("forbidden") || lower.contains("access denied") {
            return message(forHTTPStatus: 403)
        }
        if lower.contains("ffmpeg") {
            return "Couldn’t combine the video and audio (ffmpeg). Try again, or pick a different quality."
        }
        if let hls = error as? HLSDownloadError {
            return hls.errorDescription ?? "Couldn’t save this stream."
        }
        return sanitizedEngineMessage(text)
    }

    /// yt-dlp prefixes dumps with `ERROR: [youtube] id:`.
    private static func sanitizedEngineMessage(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Download failed." }
        var result = trimmed
        if result.lowercased().hasPrefix("error:") {
            result = String(result.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        if let close = result.firstIndex(of: "]") {
            let after = result[result.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if after.count > 8 { result = after }
        }
        if let colon = result.firstIndex(of: ":"),
           result[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
            let after = result[result.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if after.count > 8 { result = after }
        }
        return result
    }
}

/// Progress updates emitted while a file is transferring.
struct DownloadProgress: Sendable {
    let bytesReceived: Int64
    let totalBytes: Int64?

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return Double(bytesReceived) / Double(totalBytes)
    }
}

protocol VideoDownloading: Sendable {
    /// Downloads `remoteURL` to `destination`, yielding progress updates.
    func download(
        from remoteURL: URL,
        to destination: URL
    ) -> AsyncThrowingStream<DownloadProgress, Error>
}
