import Foundation

/// The canonical web link to a conversation — what desktop's "Copy session
/// URL" puts on the clipboard (`lib/app-routes/producerTeam.ts` builds the
/// path, `ATLAS_WEB_BASE_URL` the origin).
enum SessionLink {
    static let webBase = "https://nuphos.ai"

    /// `https://nuphos.ai/teams/<teamId>/agent/<sessionId>`, with both
    /// segments percent-encoded the way `encodeURIComponent` encodes them.
    static func url(teamId: String, sessionId: String) -> URL? {
        guard !teamId.isEmpty, !sessionId.isEmpty else { return nil }
        return URL(string: "\(webBase)/teams/\(segment(teamId))/agent/\(segment(sessionId))")
    }

    private static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathSegmentAllowed) ?? value
    }
}

private extension CharacterSet {
    /// `encodeURIComponent`'s unreserved set: everything else is escaped,
    /// including the `/` and `:` that `.urlPathAllowed` would let through.
    static let urlPathSegmentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )
}
