import SwiftUI

@main
struct GitHubPRBarApp: App {
    @State private var service = GitHubService()

    var body: some Scene {
        MenuBarExtra {
            PRMenuView(service: service)
        } label: {
            Image(systemName: "arrow.triangle.pull")
        }
        .menuBarExtraStyle(.window)
    }
}
