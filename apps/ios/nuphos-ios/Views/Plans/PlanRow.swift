import SwiftUI

/// One plan in the library: creator avatar, title, then the number,
/// progress, author and age on a dot-separated meta line, with the status
/// chip trailing — the desktop table's columns, folded into a row.
struct PlanRow: View {
    let plan: Plan
    let creator: TeamMember?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(user: creator?.asUser ?? NuphosUser(id: plan.createdBy, email: "", name: "?", username: "", avatarURL: ""), size: 36)
                .opacity(creator?.isRemoved == true ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title.isEmpty ? "Untitled plan" : plan.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.heading)
                    .lineLimit(1)

                Text(meta)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusBadge(status: plan.status)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts = [plan.displayNumber]
        let progress = plan.progress
        if progress.total > 0 {
            parts.append("\(progress.done)/\(progress.total) steps" + (progress.failed > 0 ? " · \(progress.failed) failed" : ""))
        }
        if let creator {
            parts.append(creator.isRemoved ? "\(creator.displayName) (former member)" : creator.displayName)
        }
        if let createdAt = plan.createdAt {
            parts.append(HistoryTime.format(createdAt))
        }
        return parts.joined(separator: " · ")
    }
}
