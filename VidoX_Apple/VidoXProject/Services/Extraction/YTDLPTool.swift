import Foundation
#if os(macOS)
import Darwin
#endif

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
            if let code = TransferErrorHelp.httpStatus(in: message) {
                TransferErrorHelp.message(forHTTPStatus: code)
            } else {
                message
            }
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
        "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_macos"
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

    /// Ensures a runnable yt-dlp exists. Does not wait on a version refresh.
    nonisolated static func ensureReady() async throws {
        if resolveBinaryPath() != nil {
            refreshManagedBinaryInBackgroundIfNeeded()
            return
        }
        try await downloadOfficialBinary()
        guard resolveBinaryPath() != nil else {
            throw YTDLPError.binaryNotFound
        }
    }

    /// Call at launch so the first Fetch Info isn’t blocked by a missing binary.
    nonisolated static func prepareInBackground() {
        Task.detached(priority: .utility) {
            try? await ensureReady()
        }
    }

    nonisolated private static func refreshManagedBinaryInBackgroundIfNeeded() {
        guard let path = resolveBinaryPath(), shouldRefreshManagedBinary(at: path) else { return }
        Task.detached(priority: .utility) {
            try? await downloadOfficialBinary()
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

    private static let managedBinaryMaxAge: TimeInterval = 24 * 60 * 60

    nonisolated private static func shouldRefreshManagedBinary(at path: String) -> Bool {
        guard path == managedBinaryURL.path else { return false }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = attrs?[.modificationDate] as? Date ?? .distantPast
        return Date().timeIntervalSince(modified) > managedBinaryMaxAge
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
            let staging = destination.appendingPathExtension("new")
            if FileManager.default.fileExists(atPath: staging.path) {
                try FileManager.default.removeItem(at: staging)
            }
            try FileManager.default.moveItem(at: tempURL, to: staging)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: staging.path
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch let error as YTDLPError {
            throw error
        } catch {
            throw YTDLPError.bootstrapFailed(error.localizedDescription)
        }
    }

    /// Homebrew / MacPorts tools are missing from GUI-app PATH; yt-dlp still needs them.
    nonisolated static func ffmpegPath() -> String? {
        firstExecutable(at: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg"
        ])
    }

    nonisolated private static func denoPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".deno/bin/deno").path
        return firstExecutable(at: [
            "/opt/homebrew/bin/deno",
            "/usr/local/bin/deno",
            "/opt/local/bin/deno",
            home
        ])
    }

    nonisolated private static func nodePath() -> String? {
        firstExecutable(at: [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/opt/local/bin/node"
        ])
    }

    nonisolated private static func firstExecutable(at paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func runtimeSupportArguments(forDownload: Bool) -> [String] {
        var args: [String] = []
        if forDownload, let ffmpeg = ffmpegPath() {
            args += ["--ffmpeg-location", ffmpeg]
        }
        // Deno/Node nsig solving is slow and only needed when fetching media, not listing info.
        if forDownload {
            if let deno = denoPath() {
                args += ["--js-runtimes", "deno:\(deno)"]
            } else if let node = nodePath() {
                args += ["--js-runtimes", "node:\(node)"]
            }
        }
        return args
    }

    @discardableResult
    nonisolated static func run(arguments: [String], forDownload: Bool = false) async throws -> Data {
        try await ensureReady()
        guard let binary = resolveBinaryPath() else {
            throw YTDLPError.binaryNotFound
        }

        let timeout = forDownload ? 240.0 : 12.0
        let box = ProcessBox()
        let stdout = Pipe()
        let stderr = Pipe()

        box.process.executableURL = URL(fileURLWithPath: binary)
        let cache = managedDirectory.appendingPathComponent("Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        box.process.arguments =
            ["--ignore-config", "--cache-dir", cache.path]
            + runtimeSupportArguments(forDownload: forDownload)
            + arguments
        var environment = ProcessInfo.processInfo.environment
        var extraDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        let denoBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".deno/bin").path
        extraDirs.append(denoBin)
        let extraPath = extraDirs
            .filter { FileManager.default.fileExists(atPath: $0) }
            .joined(separator: ":")
        if !extraPath.isEmpty {
            let existing = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(extraPath):\(existing)"
        }
        box.process.environment = environment
        box.process.standardOutput = stdout
        box.process.standardError = stderr

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await waitForProcess(box, stdout: stdout, stderr: stderr)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    box.terminate(timedOut: true)
                    throw YTDLPError.failed("Timed out looking up this video.")
                }
                do {
                    guard let data = try await group.next() else {
                        throw YTDLPError.failed("Download engine returned no data.")
                    }
                    group.cancelAll()
                    box.terminate()
                    return data
                } catch {
                    group.cancelAll()
                    box.terminate()
                    throw error
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    private final class ProcessBox: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private(set) var timedOut = false

        func didTimeOut() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return timedOut
        }

        func terminate(timedOut: Bool = false) {
            lock.lock()
            if timedOut { self.timedOut = true }
            let running = process.isRunning
            lock.unlock()
            guard running else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [process] in
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    private static func waitForProcess(_ box: ProcessBox, stdout: Pipe, stderr: Pipe) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let once = OnceResume(continuation)
            let collector = PipeCollector(stdout: stdout, stderr: stderr)
            collector.start()
            box.process.terminationHandler = { proc in
                let (outData, errData) = collector.finish()
                if box.didTimeOut() {
                    once.finish(.failure(YTDLPError.failed("Timed out looking up this video.")))
                    return
                }
                let errText = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if proc.terminationStatus != 0 {
                    let message = errText.isEmpty
                        ? "Downloader exited with status \(proc.terminationStatus)."
                        : errText
                    once.finish(.failure(YTDLPError.failed(message)))
                } else {
                    once.finish(.success(outData))
                }
            }
            do {
                try box.process.run()
            } catch {
                collector.finish()
                once.finish(.failure(error))
            }
        }
    }

    /// Drain pipes while yt-dlp runs so a large `-J` payload cannot deadlock the process.
    private final class PipeCollector: @unchecked Sendable {
        private let stdout: Pipe
        private let stderr: Pipe
        private let lock = NSLock()
        private var outData = Data()
        private var errData = Data()

        init(stdout: Pipe, stderr: Pipe) {
            self.stdout = stdout
            self.stderr = stderr
        }

        func start() {
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                self?.appendOut(chunk)
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                self?.appendErr(chunk)
            }
        }

        func finish() -> (Data, Data) {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            appendOut(stdout.fileHandleForReading.readDataToEndOfFile())
            appendErr(stderr.fileHandleForReading.readDataToEndOfFile())
            lock.lock()
            defer { lock.unlock() }
            return (outData, errData)
        }

        private func appendOut(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            outData.append(chunk)
            lock.unlock()
        }

        private func appendErr(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            errData.append(chunk)
            lock.unlock()
        }
    }

    private final class OnceResume: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?

        init(_ continuation: CheckedContinuation<Data, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<Data, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }
    }
}
#endif
