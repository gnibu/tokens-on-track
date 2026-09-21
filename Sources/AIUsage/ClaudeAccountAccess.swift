import Foundation

/// Security-scoped bookmarks for Claude profile folders chosen in the App Store
/// build. Credentials remain in Claude Code's Keychain items.
final class ClaudeAccountAccess: @unchecked Sendable {
    static let shared = ClaudeAccountAccess()

    private let defaults: UserDefaults
    private let bookmarks: ProviderFolderAccess.BookmarkOperations
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        bookmarks: ProviderFolderAccess.BookmarkOperations = .init()
    ) {
        self.defaults = defaults
        self.bookmarks = bookmarks
    }

    func bookmark(for normalizedPath: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.data(forKey: bookmarkKey(normalizedPath))
    }

    func storeBookmark(_ data: Data, for normalizedPath: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(data, forKey: bookmarkKey(normalizedPath))
    }

    func removeBookmark(for normalizedPath: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: bookmarkKey(normalizedPath))
    }

    /// Called only with the directory returned by the system open panel.
    func select(_ url: URL) throws -> String {
        let path = ClaudeProfile.normalizedPath(url.path)
        guard bookmarks.start(url) else { throw ProviderFolderAccess.AccessError.unavailable }
        defer { bookmarks.stop(url) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw ProviderFolderAccess.AccessError.wrongFolder("profile folder") }
        let data = try bookmarks.create(url)
        storeBookmark(data, for: path)
        return path
    }

    private func bookmarkKey(_ path: String) -> String {
        "claudeProfile.\(path)"
    }
}
