import Foundation

/// Unsent composer text per conversation, kept while the app runs and dropped on sign-out.
enum ComposerDrafts {
    private static var drafts: [String: String] = [:]

    private static func key(_ team: String, _ session: String) -> String { "\(team)/\(session)" }

    static func text(team: String, session: String) -> String {
        drafts[key(team, session)] ?? ""
    }

    static func set(_ text: String, team: String, session: String) {
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
        drafts = [:]
    }
}
