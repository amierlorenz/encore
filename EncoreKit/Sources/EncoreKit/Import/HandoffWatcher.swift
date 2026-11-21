import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.amierlorenz.Encore", category: "handoff")

#if os(macOS)
import Darwin

/// Watches the local Articulate-Encore hand-off folder on macOS and imports files as they arrive.
///
/// Rules:
/// - Watches `~/Library/Application Support/Encore/Handoff/to-encore/`.
/// - Creates `to-encore/`, `to-encore/failed/`, and `from-encore/` if missing.
/// - Imports every `import-*.json` in lexicographical name order.
/// - Skips dotfiles (e.g. `.<name>.tmp`) and temporary files until completely written and renamed.
/// - Hands `plan.json` and `postclass-*.json` to `DailyPlanStore` (or a custom plan handler).
/// - Never deletes `plan.json`.
/// - Deletes successful `import-*.json` files; moves invalid or unsupported files to `to-encore/failed/` with `<batchId>.error.txt`.
/// - Scans immediately on launch (`start()`), not only on file system events.
@MainActor
public final class HandoffWatcher {
    public struct ScanResult: Equatable, Sendable {
        public var importedFiles: [String] = []
        public var failedFiles: [String] = []
        public var planFiles: [String] = []

        public init(importedFiles: [String] = [], failedFiles: [String] = [], planFiles: [String] = []) {
            self.importedFiles = importedFiles
            self.failedFiles = failedFiles
            self.planFiles = planFiles
        }
    }

    public let handoffFolder: HandoffFolder
    public let context: ModelContext
    public var planHandler: @MainActor (URL) -> Void

    private var dispatchSource: (any DispatchSourceFileSystemObject)?
    private var directoryFileDescriptor: CInt = -1
    private var isScanning = false
    private var needsRescan = false

    public init(
        handoffFolder: HandoffFolder = HandoffFolder(),
        context: ModelContext,
        planHandler: (@MainActor (URL) -> Void)? = nil
    ) {
        self.handoffFolder = handoffFolder
        self.context = context
        self.planHandler = planHandler ?? { url in
            _ = try? DailyPlanStore.shared.loadFromFile(at: url)
        }
    }

    deinit {
        dispatchSource?.cancel()
        if directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
        }
    }

    /// Starts watching `to-encore/` and runs an initial scan immediately.
    public func start() {
        stop()
        do {
            try handoffFolder.createDirectoriesIfNeeded()
        } catch {
            logger.error("Failed to create handoff directories: \(error)")
        }

        // Initial scan on launch/start
        scan()

        let path = handoffFolder.toEncoreURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Failed to open directory for watching: \(path)")
            return
        }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let data = source.data
                if data.contains(.delete) || data.contains(.rename) {
                    self.start()
                } else {
                    self.scan()
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        dispatchSource = source
    }

    /// Stops watching `to-encore/`.
    public func stop() {
        if let source = dispatchSource {
            source.cancel()
            dispatchSource = nil
            directoryFileDescriptor = -1
        } else if directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
            directoryFileDescriptor = -1
        }
    }

    /// Scans `to-encore/` synchronously, importing waiting files in order.
    @discardableResult
    public func scan() -> ScanResult {
        guard !isScanning else {
            needsRescan = true
            return ScanResult()
        }
        isScanning = true
        defer {
            isScanning = false
            if needsRescan {
                needsRescan = false
                _ = scan()
            }
        }

        do {
            try handoffFolder.createDirectoriesIfNeeded()
        } catch {
            return ScanResult()
        }

        let fm = FileManager.default
        let toEncoreURL = handoffFolder.toEncoreURL
        guard let allURLs = try? fm.contentsOfDirectory(at: toEncoreURL, includingPropertiesForKeys: nil) else {
            return ScanResult()
        }

        // Filter out dotfiles (such as `.<name>.tmp`) and `.tmp` files
        let validURLs = allURLs.filter { url in
            let name = url.lastPathComponent
            return !name.hasPrefix(".") && !name.hasSuffix(".tmp")
        }

        // 1. Process `import-*.json` in name order
        let importURLs = validURLs
            .filter { $0.lastPathComponent.hasPrefix("import-") && $0.lastPathComponent.hasSuffix(".json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result = ScanResult()
        let importer = Importer(context: context)

        for url in importURLs {
            let filename = url.lastPathComponent
            do {
                _ = try importer.importFile(at: url, handoff: handoffFolder, deleteOnSuccess: true)
                result.importedFiles.append(filename)
                logger.info("Handoff imported: \(filename)")
            } catch {
                result.failedFiles.append(filename)
                logger.error("Handoff import failed for \(filename): \(error)")
            }
        }

        if !result.importedFiles.isEmpty {
            _ = StateExporter.exportOnLaunch(context: context, folder: handoffFolder)
        }

        // 2. Hand `plan.json` and `postclass-*.json` to planHandler in name order
        let planURLs = validURLs
            .filter {
                let name = $0.lastPathComponent
                return name == "plan.json" || (name.hasPrefix("postclass-") && name.hasSuffix(".json"))
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in planURLs {
            planHandler(url)
            result.planFiles.append(url.lastPathComponent)
        }

        return result
    }
}
#else
/// Handoff watching is Mac-only; iOS receives study data via CloudKit.
@MainActor
public final class HandoffWatcher {
    public struct ScanResult: Equatable, Sendable {
        public var importedFiles: [String] = []
        public var failedFiles: [String] = []
        public var planFiles: [String] = []

        public init(importedFiles: [String] = [], failedFiles: [String] = [], planFiles: [String] = []) {
            self.importedFiles = importedFiles
            self.failedFiles = failedFiles
            self.planFiles = planFiles
        }
    }

    public let handoffFolder: HandoffFolder

    public init(
        handoffFolder: HandoffFolder = HandoffFolder(),
        context: ModelContext,
        planHandler: (@MainActor (URL) -> Void)? = nil
    ) {
        self.handoffFolder = handoffFolder
    }

    public func start() {}
    public func stop() {}
    @discardableResult
    public func scan() -> ScanResult { ScanResult() }
}
#endif
