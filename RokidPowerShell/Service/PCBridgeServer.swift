import Foundation
import Network

/// Listens on TCP :8102 for the Windows PC companion script.
/// Receives terminal lines, sends commands back.
@MainActor
final class PCBridgeServer: ObservableObject {

    @Published var isRunning   = false
    @Published var isConnected = false   // true when a PC is connected

    /// Called with each parsed line from the PC.
    var onLine:   ((TerminalLine) -> Void)?
    /// Called when PC sends CLR:
    var onClear:  (() -> Void)?
    /// Called on connect/disconnect
    var onStatus: ((String) -> Void)?

    private var listener:   NWListener?
    private var connection: NWConnection?     // single PC connection
    private var buffer = Data()
    private let port: NWEndpoint.Port = 8102
    private let queue = DispatchQueue(label: "PCBridgeQ", qos: .userInitiated)

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
        listener?.cancel();  listener = nil
        connection?.cancel(); connection = nil
        buffer.removeAll()
        isRunning = false; isConnected = false
    }

    // MARK: - Send command to PC

    func sendCommand(_ text: String) {
        guard isConnected, let conn = connection else { return }
        conn.send(content: PSProtocol.command(text), completion: .contentProcessed { _ in })
    }

    // MARK: - Private

    private func accept(_ conn: NWConnection) {
        // Only allow one PC at a time — cancel the previous
        connection?.cancel()
        buffer.removeAll()
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.onStatus?("💻 PC connected on :8102")
                case .failed(let err):
                    self?.isConnected = false
                    self?.onStatus?("⚠️ PC disconnected (\(err.localizedDescription))")
                case .cancelled:
                    self?.isConnected = false
                    self?.onStatus?("🔌 PC disconnected")
                default: break
                }
            }
        }
        conn.start(queue: queue)
        receiveNext(conn)
    }

    private func receiveNext(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let d = data, !d.isEmpty {
                    self.buffer.append(d)
                    self.flushBuffer()
                }
                if done || err != nil {
                    self.isConnected = false
                    self.onStatus?("🔌 PC disconnected")
                } else {
                    self.receiveNext(conn)
                }
            }
        }
    }

    private func flushBuffer() {
        while let newlineIdx = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIdx]
            buffer.removeSubrange(buffer.startIndex...newlineIdx)

            guard let raw = String(data: lineData, encoding: .utf8) else { continue }

            if PSProtocol.isClear(raw) {
                onClear?()
            } else if let line = PSProtocol.parse(raw) {
                onLine?(line)
            }
        }
    }
}
