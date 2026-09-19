import Foundation

enum ProviderFolder: String, CaseIterable {
    case codex, cursor

    var name: String { self == .codex ? "Codex" : "Cursor" }
    var fileName: String { self == .codex ? "auth.json" : "state.vscdb" }
    var suggestedPath: String {
        self == .codex ? "~/.codex" : "~/Library/Application Support/Cursor/User/globalStorage"
    }
    var bookmarkKey: String { "providerFolder.\(rawValue)" }
}

/// Only bookmarks are persisted here. Provider credentials remain in their
/// original files. The security scope (not the lock) covers the entire read,
/// including SQLite's helper.
/// A folder grant survives the provider replacing its credential file.
final class ProviderFolderAccess: @unchecked Sendable {
    static let shared = ProviderFolderAccess()

    enum AccessError: LocalizedError {
        case notSelected, unavailable, wrongFolder(String), missingFile(ProviderFolder)

        var errorDescription: String? {
            switch self {
            case .notSelected: return "Choose the provider folder in Settings"
            case .unavailable: return "Folder access expired or was removed — choose it again in Settings"
            case .wrongFolder(let file): return "Choose the folder containing \(file)"
            case .missingFile(let folder): return "\(folder.fileName) not found — sign in to \(folder.name)"
            }
        }
    }

    struct BookmarkOperations {
        var create: (URL) throws -> Data = {
            try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        var resolve: (Data) throws -> (url: URL, stale: Bool) = {
            var stale = false
            let url = try URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        }
        var start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
        var stop: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    }

    private let defaults: UserDefaults
    private let bookmarks: BookmarkOperations
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, bookmarks: BookmarkOperations = .init()) {
        self.defaults = defaults
        self.bookmarks = bookmarks
    }

    func isSelected(_ folder: ProviderFolder) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.data(forKey: folder.bookmarkKey) != nil
    }

    /// Called only with the directory returned by the system open panel.
    func select(_ url: URL, for folder: ProviderFolder) throws {
        lock.lock()
        defer { lock.unlock() }
        guard bookmarks.start(url) else { throw AccessError.unavailable }
        defer { bookmarks.stop(url) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.appendingPathComponent(folder.fileName).path)
        else { throw AccessError.wrongFolder(folder.fileName) }
        // Keep the previous grant if validation or bookmark creation fails.
        let data = try bookmarks.create(url)
        defaults.set(data, forKey: folder.bookmarkKey)
    }

    func remove(_ folder: ProviderFolder) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: folder.bookmarkKey)
    }

    func withFile<T>(for folder: ProviderFolder, _ read: (URL) throws -> T) throws -> T {
        let url = try startAccess(folder)
        defer { bookmarks.stop(url) }
        let file = url.appendingPathComponent(folder.fileName)
        guard FileManager.default.isReadableFile(atPath: file.path) else { throw AccessError.missingFile(folder) }
        // Read outside the lock: Cursor's read runs sqlite3, and the main
        // thread's status checks must not wait behind it.
        return try read(file)
    }

    /// Resolves the grant and starts its scope; the caller must stop it.
    private func startAccess(_ folder: ProviderFolder) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: folder.bookmarkKey) else { throw AccessError.notSelected }
        let resolved: (url: URL, stale: Bool)
        do { resolved = try bookmarks.resolve(data) }
        catch { throw AccessError.unavailable }
        guard bookmarks.start(resolved.url) else { throw AccessError.unavailable }
        if resolved.stale {
            do { defaults.set(try bookmarks.create(resolved.url), forKey: folder.bookmarkKey) }
            catch {
                bookmarks.stop(resolved.url)
                throw AccessError.unavailable
            }
        }
        return resolved.url
    }

    func status(_ folder: ProviderFolder) -> String {
        do { return try withFile(for: folder) { _ in "Read-only access allowed" } }
        catch { return error.localizedDescription }
    }
}
