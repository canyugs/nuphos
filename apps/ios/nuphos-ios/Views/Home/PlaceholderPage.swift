import SwiftUI

/// Stand-in for the pages that are not built yet. Keeps the switcher honest
/// about what exists.
struct PlaceholderPage: View {
    let page: HomePage

    var body: some View {
        ContentUnavailableView {
            Label(page.title, systemImage: page.systemImage)
        } description: {
            Text("Coming soon to the Nuphos app.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

#Preview {
    PlaceholderPage(page: .monitoring)
}
