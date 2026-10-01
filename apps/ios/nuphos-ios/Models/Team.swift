import Foundation

/// `GET /teams` row (`AtlasTeam` on the desktop). Only what the app reads.
struct Team: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let avatarUrl: String?
    let isOwner: Bool?
    /// The caller's membership role (`ADMINISTRATOR` / `EDITOR` / `VIEWER`).
    let role: String?

    var isAdministrator: Bool { role == "ADMINISTRATOR" || isOwner == true }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner)
        role = try c.decodeIfPresent(String.self, forKey: .role)
    }

    init(id: String, name: String, avatarUrl: String? = nil, isOwner: Bool? = nil, role: String? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.isOwner = isOwner
        self.role = role
    }

    static let preview = Team(id: "64b5f1c2e4b0a1d2c3e4f5a6", name: "Zeabur", isOwner: true)
}
