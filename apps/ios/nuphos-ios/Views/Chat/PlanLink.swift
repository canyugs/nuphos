import Foundation

/// Recognises the app's own plan links — `https://nuphos.ai/teams/T/plans/N`
/// (any nuphos.ai host) or the bare path — the way the desktop's
/// `parseAtlasLink` does, so a tap opens the plan in-app instead of Safari.
enum PlanLink {
    struct Target: Equatable, Identifiable {
        let teamId: String
        let planId: String
        var id: String { teamId + "/" + planId }
    }

    static func target(in url: URL) -> Target? {
        if let host = url.host()?.lowercased() {
            guard host == "nuphos.ai" || host.hasSuffix(".nuphos.ai") else { return nil }
        } else if url.scheme != nil {
            return nil
        }
        let parts = url.path().split(separator: "/").map(String.init)
        // /teams/<teamId>/plans/<planId>
        guard parts.count >= 4, parts[0] == "teams", parts[2] == "plans", !parts[1].isEmpty, !parts[3].isEmpty else { return nil }
        return Target(teamId: parts[1], planId: parts[3])
    }
}
