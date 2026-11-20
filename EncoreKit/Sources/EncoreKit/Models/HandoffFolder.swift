import Foundation

/// Coordinates paths in the local hand-off directory between Articulate and Encore.
public struct HandoffFolder: Sendable {
    public var rootURL: URL

    public init(rootURL: URL = Self.defaultRootURL) {
        self.rootURL = rootURL
    }

    public static var defaultRootURL: URL {
        #if os(macOS)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        #else
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        #endif
        return appSupport.appending(path: "Encore/Handoff")
    }

    public var toEncoreURL: URL {
        rootURL.appending(path: "to-encore")
    }

    public var failedURL: URL {
        toEncoreURL.appending(path: "failed")
    }

    public var fromEncoreURL: URL {
        rootURL.appending(path: "from-encore")
    }

    public func createDirectoriesIfNeeded() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: toEncoreURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: failedURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: fromEncoreURL, withIntermediateDirectories: true)
    }
}
