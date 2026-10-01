import Foundation

/// The user record `GET /auth/me` returns. Mirrors `NuphosUser` in the
/// landing page (`src/utils/api.ts`); unknown fields are ignored so a
/// backend addition never breaks decoding.
struct NuphosUser: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let email: String
    let name: String
    let username: String
    let avatarURL: String

    init(id: String, email: String, name: String, username: String, avatarURL: String) {
        self.id = id
        self.email = email
        self.name = name
        self.username = username
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
    }

    /// What to call the user when a name is missing — same fallback order
    /// as the web profile menu.
    var displayName: String {
        if !name.isEmpty { return name }
        if !username.isEmpty { return username }
        return email
    }

    var avatar: URL? {
        guard !avatarURL.isEmpty else { return nil }
        return URL(string: avatarURL)
    }

    /// Ported from the desktop `Avatar` component: first letters of the
    /// first and last words, or the first two letters of a single word.
    var initials: String {
        let parts = displayName.split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first, !first.isEmpty else { return "?" }
        if parts.count == 1 { return String(first.prefix(2)).uppercased() }
        return (String(first.prefix(1)) + String(parts[parts.count - 1].prefix(1))).uppercased()
    }

    static let preview = NuphosUser(
        id: "507f1f77bcf86cd799439011",
        email: "bruce@example.com",
        name: "Bruce Wayne",
        username: "bruce",
        avatarURL: ""
    )
}
