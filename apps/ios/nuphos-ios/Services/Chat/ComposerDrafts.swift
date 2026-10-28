import Foundation

/// Account-scoped unsent drafts. Disk writes finish before returning to the composer.
enum ComposerDrafts {
    static var account: String?
    static var storage: SharedDraftStore?
    static var error: String?
    static var revision = UUID()
    static func signIn(account: String) {
        let store = SharedDraftStore.applicationGroup()
        if self.account != account {
            try? store?.revoke(account: nil)
            drafts = [:]; revision = UUID()
        }
        self.account = account
        storage = store
    }
    static func selectTeam(_ team: String) {
        guard let account else { return }
        do { _ = try storage?.activate(account: account, team: team) }
        catch { self.error = error.localizedDescription }
    }
    private static var drafts: [String: String] = [:]

    private static func key(_ team: String, _ session: String) -> String { "\(team)/\(session)" }

    static func text(team: String, session: String) -> String {
        if let account, let storage {
            do { return try storage.composer(account: account, team: team, session: session)?.text ?? "" }
            catch { self.error = error.localizedDescription }
        }
        return drafts[key(team, session)] ?? ""
    }

    static func set(_ text: String, team: String, session: String) {
        if let account, let storage {
            do { try storage.updateText(account: account, team: team, session: session, text: text) }
            catch { self.error = error.localizedDescription }
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts.removeValue(forKey: key(team, session))
        } else {
            drafts[key(team, session)] = text
        }
    }

    /// The composer text to show after the selected team changes. Text typed
    /// before any team resolved belongs to the first team, not to nobody.
    static func switchTeam(visible: String, session: String, from old: String, to new: String) -> String {
        guard old.isEmpty, !visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text(team: new, session: session)
        }
        set("", team: old, session: session)
        set(visible, team: new, session: session)
        return visible
    }

    static func clear() {
        if let storage = storage ?? SharedDraftStore.applicationGroup() {
            do {
                let currentScope = try storage.scope()
                let owner = account ?? currentScope?.account
                try storage.revoke(account: owner)
            } catch { self.error = error.localizedDescription }
        }
        drafts = [:]
        revision = UUID()
    }
}
