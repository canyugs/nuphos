import Foundation

@main struct SharedDraftStoreTests {
    static func main() throws {
        func check(_ value: @autoclosure () throws -> Bool) rethrows { let result = try value(); precondition(result) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedDraftStore(root: root)
        let scope = try store.activate(account: "a", team: "t")!
        let source = root.appendingPathComponent("source.txt"); try Data("synthetic attachment".utf8).write(to: source)
        let id = UUID()
        try store.save(id: id, scope: scope, session: nil, text: "share", files: [("note.txt", "public.plain-text", source)])
        let reopened = SharedDraftStore(root: root)
        try check(reopened.list(scope: scope).count == 1)
        try reopened.importShare(id: id, scope: scope)
        try check(reopened.list(scope: scope).isEmpty)
        let composer = try reopened.composer(account: "a", team: "t", session: "new")!
        precondition(composer.text == "share")
        try check(Data(contentsOf: reopened.fileURL(composer.files[0])) == Data("synthetic attachment".utf8))
        do { try reopened.importShare(id: id, scope: scope); fatalError("duplicate import") } catch SharedDraftStore.Failure.missing {}
        try reopened.updateText(account: "a", team: "t", session: "new", text: "edited")
        try check(SharedDraftStore(root: root).composer(account: "a", team: "t", session: "new")?.text == "edited")
        let second = UUID(); try store.save(id: second, scope: scope, session: nil, text: "another", files: [])
        do { try store.importShare(id: second, scope: scope); fatalError("overwritten") } catch SharedDraftStore.Failure.occupied {}
        let other = try store.activate(account: "b", team: "t")!
        try check(store.list(scope: other).isEmpty)
        do { try store.save(id: UUID(), scope: scope, session: nil, text: "late", files: []); fatalError("stale scope") } catch SharedDraftStore.Failure.identityChanged {}
        let returned = try store.activate(account: "a", team: "t")!
        precondition(returned != scope)
        let cancelled = UUID(); try store.save(id: cancelled, scope: returned, session: nil, text: "cancel", files: [])
        try store.discard(id: cancelled, scope: returned)
        try check(store.list(scope: returned).allSatisfy { $0.id != cancelled })
        let old = UUID(); try store.save(id: old, scope: returned, session: nil, text: "expired", files: [], now: Date(timeIntervalSinceNow: -SharedDraftStore.lifetime-1))
        try check(store.list(scope: returned).allSatisfy { $0.id != old })
        do { try store.save(id: UUID(), scope: returned, session: nil, text: String(repeating: "a", count: SharedDraftStore.maxTextBytes+1), files: []); fatalError("too large") } catch SharedDraftStore.Failure.capacity {}
        let workspace = try store.activate(account: "a", team: "other")!
        try check(store.list(scope: workspace).isEmpty)
        do { try store.discard(id: second, scope: returned); fatalError("stale workspace") } catch SharedDraftStore.Failure.identityChanged {}
        let concurrentScope = try store.activate(account: "a", team: "t")!
        let concurrent = DispatchQueue(label: "draft-tests", attributes: .concurrent)
        let group = DispatchGroup()
        for i in 0..<12 {
            group.enter(); concurrent.async {
                defer { group.leave() }
                do { try SharedDraftStore(root: root).save(id: UUID(), scope: concurrentScope, session: nil, text: "parallel \(i)", files: []) }
                catch { fatalError("concurrent write failed: \(error)") }
            }
        }
        group.wait()
        try check(store.list(scope: concurrentScope).filter { $0.text.hasPrefix("parallel") }.count == 12)
        try store.revoke(account: "a")
        try check(store.scope() == nil)
        try check(store.composer(account: "a", team: "t", session: "new") == nil)
        print("Shared draft persistence, import, expiry, capacity and identity fences passed")
    }
}
