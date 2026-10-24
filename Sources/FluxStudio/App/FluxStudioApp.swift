import SwiftUI

@main
struct FluxStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1024, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
