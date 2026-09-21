import Foundation

/// Read-only security-scoped bookmarks for Codex profile folders. The default
/// profile deliberately reuses the old single-Codex bookmark key.
final class CodexAccountAccess: @unchecked Sendable {
    static let shared = CodexAccountAccess()

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

    func isSelected(_ normalizedPath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.data(forKey: bookmarkKey(normalizedPath)) != nil
    }

    /// Called only with the directory returned by the system open panel.
    func select(_ url: URL) throws -> String {
        let path = CodexProfile.normalizedPath(url.path)
        guard bookmarks.start(url) else { throw ProviderFolderAccess.AccessError.unavailable }
        defer { bookmarks.stop(url) }
        let auth = url.appendingPathComponent(CodexProfile.authFileName)
        guard FileManager.default.isReadableFile(atPath: auth.path)
        else { throw ProviderFolderAccess.AccessError.wrongFolder(CodexProfile.authFileName) }
        let data = try bookmarks.create(url)
        lock.lock()
        defer { lock.unlock() }
        defaults.set(data, forKey: bookmarkKey(path))
        return path
    }

    func removeBookmark(for normalizedPath: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: bookmarkKey(normalizedPath))
    }

    func authData(for entry: CodexProfile.Entry) throws -> Data {
        let folder = try startAccess(entry.normalizedPath)
        defer { bookmarks.stop(folder) }
        let auth = folder.appendingPathComponent(CodexProfile.authFileName)
        guard FileManager.default.isReadableFile(atPath: auth.path)
        else { throw ProviderFolderAccess.AccessError.missingFile(.codex) }
        return try Data(contentsOf: auth)
    }

    private func startAccess(_ normalizedPath: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: bookmarkKey(normalizedPath))
        else { throw ProviderFolderAccess.AccessError.notSelected }
        let resolved: (url: URL, stale: Bool)
        do { resolved = try bookmarks.resolve(data) }
        catch { throw ProviderFolderAccess.AccessError.unavailable }
        guard bookmarks.start(resolved.url) else { throw ProviderFolderAccess.AccessError.unavailable }
        if resolved.stale {
            do { defaults.set(try bookmarks.create(resolved.url), forKey: bookmarkKey(normalizedPath)) }
            catch {
                bookmarks.stop(resolved.url)
                throw ProviderFolderAccess.AccessError.unavailable
            }
        }
        return resolved.url
    }

    private func bookmarkKey(_ normalizedPath: String) -> String {
        normalizedPath == CodexProfile.defaultNormalizedPath
            ? ProviderFolder.codex.bookmarkKey
            : "codexProfile.\(normalizedPath)"
    }
}
