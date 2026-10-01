import SwiftUI

@main
struct NuphosApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #endif
    @State private var session = AuthSession()

    var body: some Scene {
        WindowGroup {
            #if DEBUG && os(iOS)
            if CommandLine.arguments.contains("-scroll-regression") {
                TranscriptRegressionScreen()
            } else {
                RootView()
                    .environment(session)
            }
            #else
            RootView()
                .environment(session)
            #endif
        }
    }
}
