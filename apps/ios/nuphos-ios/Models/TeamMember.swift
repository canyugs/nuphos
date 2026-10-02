import Foundation

/// One row of `GET /teams/:id/members` (`TeamMember` in the desktop's
/// `types/team.ts`): a user plus their role. `removedAt` is only present
/// when the list was fetched with `includeRemoved`.
struct TeamMember: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let email: String
    let username: String
    let avatarURL: String?
    let role: String?
    let removedAt: Date?

    /// The desktop's `memberDisplayName`: name, else username, else email.
    var displayName: String {
        if !name.isEmpty { return name }
        if !username.isEmpty { return username }
        return email
    }

    var isRemoved: Bool { removedAt != nil }

    var asUser: NuphosUser {
        NuphosUser(id: id, email: email, name: name, username: username, avatarURL: avatarURL ?? "")
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        removedAt = try? c.decodeIfPresent(Date.self, forKey: .removedAt)
    }

    init(id: String, name: String, email: String, username: String = "", avatarURL: String? = nil, role: String? = nil, removedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.username = username
        self.avatarURL = avatarURL
        self.role = role
        self.removedAt = removedAt
    }
}
