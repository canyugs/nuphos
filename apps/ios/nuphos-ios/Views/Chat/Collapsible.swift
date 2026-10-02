import SwiftUI

/// Reveals `content` by animating its frame height from 0 to its natural
/// height, clipped to the container — an unfold, not a slide-in from the
/// top of the screen.
struct Collapsible<Content: View>: View {
    var expanded: Bool
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: expanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .opacity(expanded ? 1 : 0)
            .accessibilityHidden(!expanded)
            .allowsHitTesting(expanded)
    }
}
