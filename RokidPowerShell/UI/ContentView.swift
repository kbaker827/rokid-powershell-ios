import SwiftUI

struct ContentView: View {
    @StateObject private var vm = TerminalViewModel()

    var body: some View {
        TabView {
            TerminalView()
                .tabItem { Label("Terminal", systemImage: "terminal.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environmentObject(vm)
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}
