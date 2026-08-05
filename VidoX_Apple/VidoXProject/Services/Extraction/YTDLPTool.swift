import Foundation

enum YTDLPError: LocalizedError, Sendable {
    case notAvailableOnThisPlatform
    case binaryNotFound
    case bootstrapFailed(String)
    case failed(String)
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .notAvailableOnThisPlatform:
            "This download method isn’t available on this device."
        case .binaryNotFound:
            "The built-in downloader could not be prepared."
        case .bootstrapFailed(let message):
            "Could not set up the built-in downloader: \(message)"
        case .failed(let message):
            message
        case .invalidMetadata:
            "Could not read video details from the page."
        }
    }
}

#if os(macOS)
/// Manages a self-contained `yt-dlp` binary (bundled or auto-downloaded into Application Support).
/// Users do not need Homebrew or any manual package install.
enum YTDLPTool {
    private static let githubBinaryURL = URL(string:
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
    )!

    private static let managedBinaryName = "yt-dlp"

    private static var managedDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "VidoX"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Downloader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var managedBinaryURL: URL {
        managedDirectory.appendingPathComponent(managedBinaryName)
    }

    /// Ensures a runnable yt-dlp exists (bundle → cache → auto-download).
    nonisolated static func ensureReady() async throws {
        if resolveBinaryPath() != nil { return }
        try await downloadOfficialBinary()
        guard resolveBinaryPath() != nil else {
            throw YTDLPError.binaryNotFound
        }
    }

    nonisolated static func resolveBinaryPath() -> String? {
        // 1) Copied into the app bundle (optional for distributors who vendor the binary).
        if let bundled = Bundle.main.url(forResource: "yt-dlp", withExtension: nil)
            ?? Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }

        // 2) Auto-managed copy in Application Support.
        if FileManager.default.isExecutableFile(atPath: managedBinaryURL.path) {
            return managedBinaryURL.path
        }

        // 3) Optional system install if the user already has one (not required).
        for path in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    nonisolated private static func downloadOfficialBinary() async throws {
        do {
            var request = URLRequest(url: githubBinaryURL)
            request.timeoutInterval = 60
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw YTDLPError.bootstrapFailed("Download failed (HTTP \(code)).")
            }

            let destination = managedBinaryURL
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            // Make executable (GitHub asset may not preserve +x after download).
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )
        } catch let error as YTDLPError {
            throw error
        } catch {
            throw YTDLPError.bootstrapFailed(error.localizedDescription)
        }
    }

    @discardableResult
    nonisolated static func run(arguments: [String]) async throws -> Data {
        try await ensureReady()
        guard let binary = resolveBinaryPath() else {
            throw YTDLPError.binaryNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: binary)
                    process.arguments = arguments
                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr
                    try process.run()
                    process.waitUntilExit()

                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus != 0 {
                        let message = errText.isEmpty
                            ? "Downloader exited with status \(process.terminationStatus)."
                            : errText
                        continuation.resume(throwing: YTDLPError.failed(message))
                        return
                    }
                    continuation.resume(returning: outData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
