import Foundation
import Network

/// TCP server on :8101 — streams terminal lines to Rokid glasses.
/// Also receives commands FROM glasses:
///   {"type":"mic"}               → trigger iPhone mic
///   {"type":"cmd","text":"..."}  → run command directly on PC
///   {"type":"ai","text":"..."}   → convert text via AI then run on PC
@MainActor
final class GlassesServer: ObservableObject {

    @Published var isRunning   = false
    @Published var clientCount = 0

    /// Callbacks to ViewModel for inbound glasses messages
    var onMicTrigger:      (() -> Void)?
    var onGlassesCommand:  ((String) -> Void)?
    var onGlassesAI:       ((String) -> Void)?

    private var listener:    NWListener?
    private var connections: [GlassesConnection] = []
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
        connections.forEach { $0.connection.cancel() }
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
        case .output:     typeCode = "output"
        case .error:      typeCode = "error"
        case .prompt:     typeCode = "prompt"
        case .command:    typeCode = "command"
        case .system:     typeCode = "system"
        case .voice:      typeCode = "voice"
        case .aiThinking: typeCode = "ai_thinking"
        case .aiCommand:  typeCode = "ai_command"
        }
        send(type: typeCode, text: text)
    }

    /// Send a multi-line snapshot (last N lines formatted for glasses).
    func broadcastSnapshot(_ lines: [TerminalLine], format: GlassesFormat) {
        let text = buildSnapshot(lines, format: format)
        guard !text.isEmpty else { return }
        send(type: "terminal", text: text)
    }

    func broadcastClear()           { send(type: "clear",  text: "") }
    func broadcastStatus(_ msg: String) { send(type: "status", text: msg) }

    /// Tell glasses that the iPhone mic is now listening.
    func broadcastListening(_ active: Bool) {
        send(type: "voice_state", text: active ? "listening" : "idle")
    }

    /// Show voice transcript (partial or final) on glasses.
    func broadcastVoiceTranscript(_ text: String, isFinal: Bool) {
        send(type: isFinal ? "voice_final" : "voice_partial", text: text)
    }

    /// Show AI thinking / generated command on glasses.
    func broadcastAIThinking(_ text: String) {
        send(type: "ai_thinking", text: text)
    }

    func broadcastAICommand(_ cmd: String) {
        send(type: "ai_command", text: cmd)
    }

    // MARK: - Private helpers

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
        connections.forEach { $0.connection.send(content: packet, completion: .contentProcessed { _ in }) }
    }

    private func accept(_ conn: NWConnection) {
        let wrapper = GlassesConnection(connection: conn)
        conn.stateUpdateHandler = { [weak self, weak wrapper] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self, weak wrapper] in
                    guard let wrapper else { return }
                    self?.connections.removeAll { $0 === wrapper }
                    self?.clientCount = self?.connections.count ?? 0
                }
            default: break
            }
        }
        conn.start(queue: queue)
        connections.append(wrapper)
        clientCount = connections.count
        // Welcome packet
        send(type: "status", text: "Rokid PS HUD — tap mic or speak a command")
        // Start receive loop for inbound messages from glasses
        receiveNext(wrapper)
    }

    // MARK: - Receive from glasses

    private func receiveNext(_ wrapper: GlassesConnection) {
        wrapper.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak wrapper] data, _, done, err in
            Task { @MainActor [weak self, weak wrapper] in
                guard let self, let wrapper else { return }
                if let d = data, !d.isEmpty {
                    wrapper.buffer.append(d)
                    self.flushInbound(wrapper)
                }
                if done || err != nil {
                    // connection ended — handled by stateUpdateHandler
                } else {
                    self.receiveNext(wrapper)
                }
            }
        }
    }

    private func flushInbound(_ wrapper: GlassesConnection) {
        while let newlineIdx = wrapper.buffer.firstIndex(of: 0x0A) {
            let lineData = wrapper.buffer[wrapper.buffer.startIndex..<newlineIdx]
            wrapper.buffer.removeSubrange(wrapper.buffer.startIndex...newlineIdx)
            guard let raw = String(data: lineData, encoding: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: String],
                  let type = json["type"] else { continue }
            handleInbound(type: type, text: json["text"] ?? "")
        }
    }

    private func handleInbound(type: String, text: String) {
        switch type {
        case "mic":
            onMicTrigger?()
        case "cmd":
            if !text.isEmpty { onGlassesCommand?(text) }
        case "ai":
            if !text.isEmpty { onGlassesAI?(text) }
        default:
            break
        }
    }
}

// MARK: - Per-connection wrapper

private final class GlassesConnection {
    let connection: NWConnection
    var buffer = Data()
    init(connection: NWConnection) { self.connection = connection }
}
