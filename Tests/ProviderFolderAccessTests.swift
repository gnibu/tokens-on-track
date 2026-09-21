import Foundation

enum ProviderFolderAccessTests {
    static func run() {
        runProviderFolders()
        runCodexProfiles()
    }

    private static func runProviderFolders() {
        let suite = "ProviderFolderAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let auth = root.appendingPathComponent("auth.json")
            try Data("first".utf8).write(to: auth)
            var starts = 0
            var stops = 0
            var stale = false
            var denied = false
            var failCreation = false
            var creations = 0
            let operations = ProviderFolderAccess.BookmarkOperations(
                create: { url in
                    if failCreation { throw CocoaError(.fileWriteNoPermission) }
                    creations += 1
                    return Data(url.path.utf8)
                },
                resolve: { data in
                    guard let path = String(data: data, encoding: .utf8), path.hasPrefix("/") else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    return (URL(fileURLWithPath: path), stale)
                },
                start: { _ in
                    guard !denied else { return false }
                    starts += 1
                    return true
                },
                stop: { _ in stops += 1 }
            )
            let access = ProviderFolderAccess(defaults: defaults, bookmarks: operations)
            expectFailure("missing selection") { try access.withFile(for: .codex) { _ in fatalError("read without a grant") } }
            try access.select(root, for: .codex)
            require(access.isSelected(.codex), "selection persists")
            require(starts == stops, "selection releases scope")

            // A fresh manager resolves the persisted bookmark rather than an
            // in-memory URL; an atomic credential replacement remains readable.
            let relaunched = ProviderFolderAccess(defaults: defaults, bookmarks: operations)
            try Data("replacement".utf8).write(to: auth, options: .atomic)
            let data = try relaunched.withFile(for: .codex) { url in
                require(starts == stops + 1, "scope is held during the read")
                return try Data(contentsOf: url)
            }
            require(data == Data("replacement".utf8), "reads replaced credential after relaunch")
            require(starts == stops, "read releases scope")

            stale = true
            _ = try access.withFile(for: .codex) { $0 }
            require(creations == 2, "stale bookmark is renewed")
            failCreation = true
            expectFailure("stale renewal failure") { try access.withFile(for: .codex) { _ in fatalError("read after failed renewal") } }
            require(starts == stops, "renewal failure releases scope")
            stale = false
            expectFailure("failed replacement preserves old grant") { try access.select(root, for: .codex) }
            failCreation = false
            require(access.isSelected(.codex), "old grant survives failed selection")

            denied = true
            expectFailure("revoked grant") { try access.withFile(for: .codex) { _ in fatalError("read after revocation") } }
            require(access.status(.codex).contains("choose it again"), "revoked permission gives recovery instructions")
            denied = false
            expectFailure("wrong provider folder") { try access.select(root, for: .cursor) }
            require(!access.isSelected(.cursor), "wrong folder is not saved")

            expectFailure("throwing reader") { try access.withFile(for: .codex) { _ in throw CocoaError(.fileReadUnknown) } }
            require(starts == stops, "throwing reader releases scope")
            defaults.set(Data("corrupt".utf8), forKey: ProviderFolder.codex.bookmarkKey)
            expectFailure("corrupt bookmark") { try access.withFile(for: .codex) { _ in fatalError("read with corrupt bookmark") } }
            try access.select(root, for: .codex)
            try FileManager.default.removeItem(at: auth)
            expectFailure("deleted credential") { try access.withFile(for: .codex) { _ in fatalError("read deleted file") } }
            require(access.status(.codex).contains("sign in to Codex"), "missing file does not ask to re-choose the folder")
            require(starts == stops, "missing file releases scope")
            access.remove(.codex)
            require(!access.isSelected(.codex), "remove forgets the grant")
            expectFailure("removed grant") { try access.withFile(for: .codex) { _ in fatalError("read after remove") } }
        } catch { fatalError("Folder access tests: \(error)") }
    }

    private static func runCodexProfiles() {
        let suite = "CodexAccountAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let auth = root.appendingPathComponent(CodexProfile.authFileName)
            try Data("profile-auth".utf8).write(to: auth)
            var starts = 0
            var stops = 0
            let operations = ProviderFolderAccess.BookmarkOperations(
                create: { Data($0.path.utf8) },
                resolve: { data in
                    guard let path = String(data: data, encoding: .utf8) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    return (URL(fileURLWithPath: path), false)
                },
                start: { _ in starts += 1; return true },
                stop: { _ in stops += 1 }
            )
            let access = CodexAccountAccess(defaults: defaults, bookmarks: operations)
            let path = try access.select(root)
            let entry = CodexProfile.Entry(
                normalizedPath: path,
                providerID: CodexProfile.providerID(for: path),
                source: .configured,
                preferenceRank: 1
            )
            require(access.isSelected(path), "Codex profile bookmark persists")
            require(try access.authData(for: entry) == Data("profile-auth".utf8), "Codex profile auth is readable")

            // Existing Store installs saved the default profile under this key.
            defaults.set(Data(root.path.utf8), forKey: ProviderFolder.codex.bookmarkKey)
            let defaultEntry = CodexProfile.Entry(
                normalizedPath: CodexProfile.defaultNormalizedPath,
                providerID: CodexProfile.defaultID,
                source: .default,
                preferenceRank: 2
            )
            require(
                try access.authData(for: defaultEntry) == Data("profile-auth".utf8),
                "the legacy default Codex bookmark remains readable"
            )
            access.removeBookmark(for: CodexProfile.defaultNormalizedPath)
            require(
                !access.isSelected(CodexProfile.defaultNormalizedPath),
                "removing the default Codex profile forgets its legacy bookmark"
            )
            require(starts == stops, "Codex profile reads release their security scopes")
            access.removeBookmark(for: path)
            require(!access.isSelected(path), "removing a Codex profile forgets its bookmark")
        } catch { fatalError("Codex account access tests: \(error)") }
    }

    private static func require(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }

    private static func expectFailure<T>(_ message: String, _ body: () throws -> T) {
        do { _ = try body(); fatalError("Expected failure: \(message)") }
        catch { /* Expected. */ }
    }
}
