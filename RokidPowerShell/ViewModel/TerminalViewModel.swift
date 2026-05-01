import Foundation
import Combine
import Network

@MainActor
final class TerminalViewModel: ObservableObject {

    // MARK: - Published state
    @Published var lines:           [TerminalLine] = []
    @Published var draft:           String         = ""
    @Published var glassesFormat:   GlassesFormat  = .lastLines
    @Published var lineLimit:       Int            = 500
    @Published var truncateWidth:   Int            = 55
    @Published var streamToGlasses: Bool           = true
    @Published var snapshotMode:    Bool           = false   // true = send full snapshot each line; false = stream each line

    // MARK: - Sub-objects
    let pcBridge      = PCBridgeServer()
    let glassesServer = GlassesServer()

    // MARK: - Computed
    var isPCConnected:    Bool { pcBridge.isConnected }
    var isGlassesWatching: Bool { glassesServer.clientCount > 0 }

    // MARK: - Init

    init() {
        loadSettings()

        pcBridge.onLine = { [weak self] line in
            Task { @MainActor [weak self] in self?.appendLine(line) }
        }
        pcBridge.onClear = { [weak self] in
            Task { @MainActor [weak self] in self?.clearTerminal() }
        }
        pcBridge.onStatus = { [weak self] msg in
            Task { @MainActor [weak self] in
                let sysLine = TerminalLine(text: msg, type: .system)
                self?.appendLine(sysLine)
            }
        }

        pcBridge.start()
        glassesServer.start()
    }

    // MARK: - Terminal management

    private func appendLine(_ line: TerminalLine) {
        lines.append(line)
        // Trim to limit
        if lines.count > lineLimit {
            lines.removeFirst(lines.count - lineLimit)
        }
        // Forward to glasses
        guard streamToGlasses, glassesServer.clientCount > 0 else { return }
        if snapshotMode {
            glassesServer.broadcastSnapshot(lines, format: glassesFormat)
        } else {
            glassesServer.broadcastLine(line, truncateAt: truncateWidth)
        }
    }

    func clearTerminal() {
        lines.removeAll()
        glassesServer.broadcastClear()
    }

    // MARK: - Send command to PC

    func sendCommand() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""

        // Echo locally
        let cmdLine = TerminalLine(text: "> \(text)", type: .command)
        appendLine(cmdLine)

        pcBridge.sendCommand(text)
    }

    func sendCommand(_ text: String) {
        guard !text.isEmpty else { return }
        let cmdLine = TerminalLine(text: "> \(text)", type: .command)
        appendLine(cmdLine)
        pcBridge.sendCommand(text)
    }

    // MARK: - Quick commands

    var quickCommands: [String] {
        [
            "Get-Process | Select-Object -First 10",
            "Get-Service | Where-Object Status -eq Running",
            "Get-Date",
            "Get-ComputerInfo | Select-Object CsName, OsName",
            "Get-Disk",
            "Get-NetIPAddress | Where-Object AddressFamily -eq IPv4",
            "Get-EventLog -LogName System -Newest 5",
            "Clear-Host"
        ]
    }

    // MARK: - Settings persistence

    func setGlassesFormat(_ fmt: GlassesFormat) {
        glassesFormat = fmt
        UserDefaults.standard.set(fmt.rawValue, forKey: "ps_glasses_format")
    }

    func setStreamToGlasses(_ val: Bool) {
        streamToGlasses = val
        UserDefaults.standard.set(val, forKey: "ps_stream_glasses")
        if !val { glassesServer.broadcastStatus("Streaming paused") }
    }

    func setSnapshotMode(_ val: Bool) {
        snapshotMode = val
        UserDefaults.standard.set(val, forKey: "ps_snapshot_mode")
    }

    func setTruncateWidth(_ val: Int) {
        truncateWidth = val
        UserDefaults.standard.set(val, forKey: "ps_truncate_width")
    }

    private func loadSettings() {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: "ps_glasses_format"),
           let fmt  = GlassesFormat(rawValue: raw) { glassesFormat = fmt }
        streamToGlasses = ud.object(forKey: "ps_stream_glasses") as? Bool ?? true
        snapshotMode    = ud.object(forKey: "ps_snapshot_mode")  as? Bool ?? false
        truncateWidth   = ud.integer(forKey: "ps_truncate_width").nonZero ?? 55
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
