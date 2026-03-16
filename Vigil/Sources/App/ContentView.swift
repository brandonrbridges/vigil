import SwiftUI

struct ContentView: View {
    @Environment(ServerManager.self) private var serverManager

    var body: some View {
        Group {
            if serverManager.servers.isEmpty {
                WelcomeView()
            } else {
                MainView()
            }
        }
    }
}
