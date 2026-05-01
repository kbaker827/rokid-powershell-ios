import SwiftUI
import Network

struct SettingsView: View {
    @EnvironmentObject private var vm: TerminalViewModel
    @State private var localIP: String = "—"

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Connection info
                Section("Connection") {
                    LabeledContent("iPhone IP",    value: localIP)
                    LabeledContent("PC → iPhone",  value: ":8102")
                        .foregroundStyle(.secondary)
                    LabeledContent("iPhone → Glasses", value: ":8101")
                        .foregroundStyle(.secondary)

                    HStack {
                        Circle().fill(vm.isPCConnected ? .green : .red).frame(width: 8, height: 8)
                        Text(vm.isPCConnected ? "PC connected" : "Waiting for PC")
                            .foregroundStyle(vm.isPCConnected ? .green : .secondary)
                    }
                    HStack {
                        Circle().fill(vm.glassesServer.isRunning ? .cyan : .red).frame(width: 8, height: 8)
                        Text(vm.isGlassesWatching ? "\(vm.glassesServer.clientCount) glasses connected" : "No glasses connected")
                            .foregroundStyle(vm.isGlassesWatching ? .cyan : .secondary)
                    }
                }

                // MARK: Companion script instructions
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On your Windows PC, run:")
                            .font(.footnote.weight(.semibold))
                        Text("PSCompanion.ps1 -iPhoneIP \(localIP)")
                            .font(.system(.footnote, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                        Text("The script is included in the GitHub repo root.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Companion Script")
                }

                // MARK: Glasses display
                Section("Glasses Display") {
                    Toggle("Stream to glasses", isOn: Binding(
                        get:  { vm.streamToGlasses },
                        set:  { vm.setStreamToGlasses($0) }
                    ))

                    Toggle("Snapshot mode", isOn: Binding(
                        get:  { vm.snapshotMode },
                        set:  { vm.setSnapshotMode($0) }
                    ))
                    Text(vm.snapshotMode
                         ? "Sends last N lines as one packet on each update."
                         : "Sends each new line immediately as it arrives.")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("Format", selection: Binding(
                        get:  { vm.glassesFormat },
                        set:  { vm.setGlassesFormat($0) }
                    )) {
                        ForEach(GlassesFormat.allCases) { fmt in
                            VStack(alignment: .leading) {
                                Text(fmt.displayName)
                                Text(fmt.description).font(.caption).foregroundStyle(.secondary)
                            }.tag(fmt)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Line truncation")
                            Spacer()
                            Text("\(vm.truncateWidth) chars").foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(vm.truncateWidth) },
                            set: { vm.setTruncateWidth(Int($0)) }
                        ), in: 20...80, step: 5)
                    }
                }

                // MARK: About
                Section("About") {
                    LabeledContent("App",      value: "Rokid PowerShell HUD")
                    LabeledContent("Protocol", value: "TCP :8102 (PC) + :8101 (glasses)")
                    LabeledContent("Version",  value: "1.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear { localIP = getLocalIP() ?? "Check Wi-Fi" }
        }
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            if (flags & IFF_UP) != 0,
               (flags & IFF_LOOPBACK) == 0,
               ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return address
    }
}
