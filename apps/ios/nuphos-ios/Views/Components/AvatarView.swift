import SwiftUI

/// Port of the desktop `Avatar`: the picture when there is one, otherwise
/// initials on the violet gradient.
struct AvatarView: View {
    let user: NuphosUser
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let url = user.avatar {
                CachedAvatarImage(url: url, placeholder: { fallback })
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityLabel(user.displayName)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.violet500, Theme.violet700],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(user.initials)
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// `AsyncImage` starts every appearance from nothing, so returning to the
/// chat list drops every avatar back to its initials until the pictures
/// download again. Decoded images are kept in memory and read back
/// synchronously, so an avatar seen once renders on the first frame.
private struct CachedAvatarImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: Image?

    var body: some View {
        Group {
            if let image = image ?? AvatarImageCache.shared.image(for: url) {
                image.resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard AvatarImageCache.shared.image(for: url) == nil else { return }
            image = await AvatarImageCache.shared.load(url)
        }
    }
}

/// Small in-memory cache. Avatars are few, tiny, and re-shown constantly;
/// `URLCache` alone still costs a decode and a frame of placeholder.
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()

    private var images: [URL: Image] = [:]
    private var inFlight: [URL: Task<Image?, Never>] = [:]

    func image(for url: URL) -> Image? { images[url] }

    func load(_ url: URL) async -> Image? {
        if let image = images[url] { return image }
        if let task = inFlight[url] { return await task.value }
        let task = Task<Image?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let platformImage = UIImage(data: data) else { return nil }
            return Image(uiImage: platformImage)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { images[url] = image }
        return image
    }
}

#Preview {
    HStack(spacing: 16) {
        AvatarView(user: .preview)
        AvatarView(user: .preview, size: 40)
    }
    .padding()
    .background(Theme.canvas)
}
