import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Shared by the app and extension. Contains content and opaque scope IDs, never credentials.
nonisolated struct DraftScope: Codable, Equatable { let account: String; let team: String; let lease: UUID }
nonisolated struct DraftFile: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let type: String
    let bytes: Int
}
nonisolated struct SavedDraft: Codable, Identifiable, Equatable {
    let id: UUID
    let account: String
    let team: String
    let session: String?
    var text: String
    var files: [DraftFile]
    var updated: Date
}

nonisolated final class SharedDraftStore {
    static let group = "group.ai.nuphos.ios.drafts"
    static let lifetime: TimeInterval = 7 * 24 * 3600
    static let maxBytes = 100 * 1024 * 1024
    static let maxFileBytes = 20 * 1024 * 1024
    static let maxTextBytes = 256 * 1024
    static let maxFiles = 10
    let root: URL
    private let manager = FileManager.default
    private struct Index: Codable { var scope: DraftScope?; var drafts: [SavedDraft] = [] }
    enum Failure: LocalizedError {
        case unavailable, identityChanged, capacity, invalidFile, missing, occupied
        var errorDescription: String? {
            switch self {
            case .unavailable: "Shared drafts are unavailable. Open Nuphos and select a workspace first."
            case .identityChanged: "Your account or workspace changed. Open Nuphos and share again."
            case .capacity: "Draft storage is full. Use up to 10 files, 20 MB each, 256 KB of text and 100 MB total."
            case .invalidFile: "This item could not be read. No content was saved."
            case .missing: "This draft has expired or was already used."
            case .occupied: "The composer already has a draft. Send or discard it before using this share."
            }
        }
    }
    init(root: URL) { self.root = root }
    static func applicationGroup() -> SharedDraftStore? {
        #if os(iOS)
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return SharedDraftStore(root: root.appendingPathComponent("Drafts-v1", isDirectory: true))
        #else
        return nil
        #endif
    }
    private func locked<T>(_ operation: (inout Index) throws -> T) throws -> T {
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var directory = root; try directory.setResourceValues(values)
        let fd = open(root.appendingPathComponent("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw Failure.unavailable }
        defer { flock(fd, LOCK_UN) }
        let url = root.appendingPathComponent("index.json")
        var index: Index
        if manager.fileExists(atPath: url.path) {
            index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
        } else { index = Index() }
        index.drafts.removeAll { Date().timeIntervalSince($0.updated) > Self.lifetime }
        let result = try operation(&index)
        guard index.drafts.count <= 100,
              index.drafts.reduce(0, { $0 + $1.text.utf8.count + $1.files.reduce(0) { $0 + $1.bytes } }) <= Self.maxBytes else { throw Failure.capacity }
        try JSONEncoder().encode(index).write(to: url, options: [.atomic, .completeFileProtection])
        let retained = Set(index.drafts.flatMap(\.files).map { $0.id.uuidString })
        for file in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            if UUID(uuidString: file.lastPathComponent) != nil, !retained.contains(file.lastPathComponent) { try? manager.removeItem(at: file) }
        }
        return result
    }
    func activate(account: String, team: String) throws -> DraftScope? {
        try locked { index in
            guard !account.isEmpty, !team.isEmpty else { index.scope = nil; return nil }
            if let scope = index.scope, scope.account == account, scope.team == team { return scope }
            let scope = DraftScope(account: account, team: team, lease: UUID()); index.scope = scope; return scope
        }
    }
    func scope() throws -> DraftScope? { try locked { $0.scope } }
    func revoke(account: String?) throws {
        try locked { index in
            index.scope = nil
            if let account { index.drafts.removeAll { $0.account == account } }
        }
    }
    func list(scope: DraftScope) throws -> [SavedDraft] {
        try locked { index in
            guard index.scope == scope else { throw Failure.identityChanged }
            return index.drafts.filter { $0.account == scope.account && $0.team == scope.team && $0.session == nil }.sorted { $0.updated > $1.updated }
        }
    }
    func composer(account: String, team: String, session: String) throws -> SavedDraft? {
        try locked { index in index.drafts.first { $0.account == account && $0.team == team && $0.session == session } }
    }
    func fileURL(_ file: DraftFile) -> URL { root.appendingPathComponent(file.id.uuidString) }
    /// File data is copied while holding the cross-process lock and before the atomic index commit.
    func save(id: UUID, scope: DraftScope, session: String?, text: String, files: [(String, String, URL)], now: Date = Date()) throws {
        guard text.utf8.count <= Self.maxTextBytes, files.count <= Self.maxFiles else { throw Failure.capacity }
        try locked { index in
            guard index.scope == scope else { throw Failure.identityChanged }
            if let old = index.drafts.first(where: { $0.id == id }), old.account != scope.account || old.team != scope.team { throw Failure.identityChanged }
            var copied: [DraftFile] = []; var created: [URL] = []
            do {
                let used = index.drafts.filter { $0.id != id }.reduce(0) { $0 + $1.text.utf8.count + $1.files.reduce(0) { $0 + $1.bytes } }
                var total = used + text.utf8.count
                for (name, type, source) in files {
                    let info = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                    guard info.isRegularFile == true, info.isSymbolicLink != true, let bytes = info.fileSize, bytes >= 0 else { throw Failure.invalidFile }
                    guard bytes <= Self.maxFileBytes else { throw Failure.capacity }; total += bytes
                    guard total <= Self.maxBytes else { throw Failure.capacity }
                    let file = DraftFile(id: UUID(), name: URL(fileURLWithPath: name).lastPathComponent, type: type, bytes: bytes)
                    let target = fileURL(file); try manager.copyItem(at: source, to: target); created.append(target)
                    guard try target.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes else { throw Failure.invalidFile }
                    #if os(iOS)
                    try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
                    #endif
                    copied.append(file)
                }
                guard total <= Self.maxBytes else { throw Failure.capacity }
                index.drafts.removeAll { $0.id == id || (session != nil && $0.account == scope.account && $0.team == scope.team && $0.session == session) }
                if !text.isEmpty || !copied.isEmpty { index.drafts.append(SavedDraft(id: id, account: scope.account, team: scope.team, session: session, text: text, files: copied, updated: now)) }
            } catch { for url in created { try? manager.removeItem(at: url) }; throw error }
        }
    }
    func updateText(account: String, team: String, session: String, text: String) throws {
        guard text.utf8.count <= Self.maxTextBytes else { throw Failure.capacity }
        try locked { index in
            guard index.scope?.account == account, index.scope?.team == team else { throw Failure.identityChanged }
            let position = index.drafts.firstIndex { $0.account == account && $0.team == team && $0.session == session }
            if let position {
                index.drafts[position].text = text; index.drafts[position].updated = Date()
                if text.isEmpty && index.drafts[position].files.isEmpty { index.drafts.remove(at: position) }
            } else if !text.isEmpty {
                index.drafts.append(SavedDraft(id: UUID(), account: account, team: team, session: session, text: text, files: [], updated: Date()))
            }
        }
    }
    func discard(id: UUID, scope: DraftScope) throws {
        try locked { index in
            guard index.scope == scope else { throw Failure.identityChanged }
            index.drafts.removeAll { $0.id == id && $0.account == scope.account && $0.team == scope.team }
        }
    }
    func editShare(id: UUID, scope: DraftScope, text: String) throws {
        guard text.utf8.count <= Self.maxTextBytes else { throw Failure.capacity }
        try locked { index in
            guard index.scope == scope else { throw Failure.identityChanged }
            guard let i = index.drafts.firstIndex(where: { $0.id == id && $0.account == scope.account && $0.team == scope.team && $0.session == nil }) else { throw Failure.missing }
            index.drafts[i].text = text; index.drafts[i].updated = Date()
        }
    }
    func importShare(id: UUID, scope: DraftScope) throws {
        try locked { index in
            guard index.scope == scope else { throw Failure.identityChanged }
            guard let i = index.drafts.firstIndex(where: { $0.id == id && $0.account == scope.account && $0.team == scope.team && $0.session == nil }) else { throw Failure.missing }
            guard !index.drafts.contains(where: { $0.account == scope.account && $0.team == scope.team && $0.session == "new" }) else { throw Failure.occupied }
            let old = index.drafts.remove(at: i)
            index.drafts.append(SavedDraft(id: old.id, account: old.account, team: old.team, session: "new", text: old.text, files: old.files, updated: Date()))
        }
    }
}
