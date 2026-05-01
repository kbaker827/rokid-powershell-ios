import Foundation
import Network

/// TCP server on :8101 — streams terminal lines to Rokid glasses.
@MainActor
final class GlassesServer: ObservableObject {

    @Published var isRunning   = false
    @Published var clientCount = 0

    private var listener:    NWListener?
    private var connections: [NWConnection] = []
    private let port: NWEndpoint.Port = 8101
    private let queue = DispatchQueue(label: "PSGlassesQ", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard let l = try? NWListener(using: .tcp, on: port) else { return }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in self?.isRunning = (state == .ready) }
        }
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        clientCount = 0; isRunning = false
    }

    // MARK: - Broadcast

    /// Send a single terminal line to all glasses.
    func broadcastLine(_ line: TerminalLine, truncateAt: Int = 55) {
        let text = line.truncated(to: truncateAt)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let typeCode: String
        switch line.type {
        case .output:  typeCode = "output"
        case .error:   typeCode = "error"
        case .prompt:  typeCode = "prompt"
        case .command: typeCode = "command"
        case .system:  typeCode = "system"
        }
        send(type: typeCode, text: text)
    }

    /// Send a multi-line snapshot (last N lines formatted for glasses).
    func broadcastSnapshot(_ lines: [TerminalLine], format: GlassesFormat) {
        let text = buildSnapshot(lines, format: format)
        guard !text.isEmpty else { return }
        send(type: "terminal", text: text)
    }

    func broadcastClear() { send(type: "clear", text: "") }

    func broadcastStatus(_ msg: String) { send(type: "status", text: msg) }

    // MARK: - Private

    private func buildSnapshot(_ lines: [TerminalLine], format: GlassesFormat) -> String {
        switch format {
        case .lastLines:
            return lines.suffix(3).map { $0.truncated(to: 52) }.joined(separator: "\n")

        case .outputOnly:
            let filtered = lines.filter { $0.type == .output || $0.type == .error }
            return filtered.suffix(3).map { $0.truncated(to: 52) }.joined(separator: "\n")

        case .minimal:
            let prompt = lines.last(where: { $0.type == .prompt })?.truncated(to: 30) ?? ""
            let output = lines.last(where: { $0.type == .output || $0.type == .error })?.truncated(to: 52) ?? ""
            return [prompt, output].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    private func send(type: String, text: String) {
        let dict: [String: String] = ["type": type, "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let packet = data + Data([0x0A])
        connections.forEach { $0.send(content: packet, completion: .contentProcessed { _ in }) }
    }

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.connections.removeAll { $0 === conn }
                    self?.clientCount = self?.connections.count ?? 0
                }
            default: break
            }
        }
        conn.start(queue: queue)
        connections.append(conn)
        clientCount = connections.count
        // Send welcome
        send(type: "status", text: "Rokid PS HUD connected — waiting for PowerShell on :8102")
    }
}
