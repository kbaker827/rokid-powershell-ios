import Foundation
import Combine

@MainActor
final class TerminalViewModel: ObservableObject {

    // MARK: - Terminal state
    @Published var lines:           [TerminalLine] = []
    @Published var draft:           String         = ""
    @Published var glassesFormat:   GlassesFormat  = .lastLines
    @Published var lineLimit:       Int            = 500
    @Published var truncateWidth:   Int            = 55
    @Published var streamToGlasses: Bool           = true
    @Published var snapshotMode:    Bool           = false

    // MARK: - Voice state
    @Published var voiceMode:       VoiceMode      = .direct
    @Published var isListening:     Bool           = false
    @Published var isAIThinking:    Bool           = false
    @Published var voiceStatusText: String         = ""

    // MARK: - AI settings
    @Published var aiProvider:      AICommandManager.AIProvider = .openAI
    @Published var aiApiKey:        String         = ""
    @Published var aiModel:         String         = ""    // empty = use provider default

    // MARK: - Sub-objects
    let pcBridge       = PCBridgeServer()
    let glassesServer  = GlassesServer()
    let speech         = SpeechManager()
    private let ai     = AICommandManager()

    // MARK: - Computed
    var isPCConnected:     Bool { pcBridge.isConnected }
    var isGlassesWatching: Bool { glassesServer.clientCount > 0 }

    // MARK: - Init

    init() {
        loadSettings()
        wirePCBridge()
        wireGlassesCallbacks()
        wireSpeech()
        pcBridge.start()
        glassesServer.start()
        speech.requestPermissions()
    }

    // MARK: - Wiring

    private func wirePCBridge() {
        pcBridge.onLine = { [weak self] line in
            Task { @MainActor [weak self] in self?.appendLine(line) }
        }
        pcBridge.onClear = { [weak self] in
            Task { @MainActor [weak self] in self?.clearTerminal() }
        }
        pcBridge.onStatus = { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.appendLine(TerminalLine(text: msg, type: .system))
            }
        }
    }

    private func wireGlassesCallbacks() {
        // Glasses sends {"type":"mic"} → start listening
        glassesServer.onMicTrigger = { [weak self] in
            Task { @MainActor [weak self] in self?.toggleVoice() }
        }
        // Glasses sends {"type":"cmd","text":"..."} → run directly
        glassesServer.onGlassesCommand = { [weak self] text in
            Task { @MainActor [weak self] in self?.sendCommand(text) }
        }
        // Glasses sends {"type":"ai","text":"..."} → convert via AI then run
        glassesServer.onGlassesAI = { [weak self] text in
            Task { @MainActor [weak self] in
                await self?.processAIInput(text)
            }
        }
    }

    private func wireSpeech() {
        speech.onPartialTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.voiceStatusText = "🎤 \(text)"
                self?.glassesServer.broadcastVoiceTranscript(text, isFinal: false)
            }
        }
        speech.onFinalTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.isListening = false
                self?.voiceStatusText = ""
                self?.glassesServer.broadcastListening(false)
                self?.appendLine(TerminalLine(text: "🎤 \(text)", type: .voice))
                self?.glassesServer.broadcastVoiceTranscript(text, isFinal: true)
                await self?.processVoiceInput(text)
            }
        }
        speech.onError = { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.isListening = false
                self?.voiceStatusText = ""
                self?.appendLine(TerminalLine(text: "⚠️ Voice: \(msg)", type: .system))
            }
        }
    }

    // MARK: - Voice

    func toggleVoice() {
        if isListening {
            speech.stopListening()
            isListening = false
            voiceStatusText = ""
            glassesServer.broadcastListening(false)
        } else {
            guard speech.isAvailable else {
                appendLine(TerminalLine(text: "⚠️ Mic not available — check Settings > Privacy", type: .system))
                return
            }
            isListening = true
            voiceStatusText = "🎤 Listening…"
            glassesServer.broadcastListening(true)
            speech.startListening()
        }
    }

    func cancelVoice() {
        speech.cancel()
        isListening = false
        voiceStatusText = ""
        glassesServer.broadcastListening(false)
    }

    // MARK: - Voice → command processing

    private func processVoiceInput(_ text: String) async {
        switch voiceMode {
        case .direct:
            // Treat as a PS command directly
            sendCommand(text)

        case .ai:
            await processAIInput(text)
        }
    }

    private func processAIInput(_ text: String) async {
        guard !aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLine(TerminalLine(text: "⚠️ No AI API key — add one in Settings", type: .system))
            glassesServer.broadcastStatus("No AI API key set")
            return
        }

        isAIThinking = true
        let thinkingText = "🤖 Converting: \(text)"
        appendLine(TerminalLine(text: thinkingText, type: .aiThinking))
        glassesServer.broadcastAIThinking("AI thinking…")

        do {
            let cmd = try await ai.convert(
                text:     text,
                provider: aiProvider,
                apiKey:   aiApiKey,
                model:    aiModel.isEmpty ? nil : aiModel
            )
            isAIThinking = false
            appendLine(TerminalLine(text: "✨ \(cmd)", type: .aiCommand))
            glassesServer.broadcastAICommand(cmd)
            // Auto-execute
            sendCommand(cmd)
        } catch {
            isAIThinking = false
            let msg = error.localizedDescription
            appendLine(TerminalLine(text: "⚠️ AI error: \(msg)", type: .error))
            glassesServer.broadcastStatus("AI error: \(msg)")
        }
    }

    // MARK: - Terminal management

    private func appendLine(_ line: TerminalLine) {
        lines.append(line)
        if lines.count > lineLimit {
            lines.removeFirst(lines.count - lineLimit)
        }
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
    func setVoiceMode(_ mode: VoiceMode) {
        voiceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "ps_voice_mode")
    }
    func setAIProvider(_ p: AICommandManager.AIProvider) {
        aiProvider = p
        aiModel    = p.defaultModel   // reset to default when switching
        UserDefaults.standard.set(p.rawValue, forKey: "ps_ai_provider")
    }
    func setAIApiKey(_ key: String) {
        aiApiKey = key
        UserDefaults.standard.set(key, forKey: "ps_ai_api_key")
    }
    func setAIModel(_ m: String) {
        aiModel = m
        UserDefaults.standard.set(m, forKey: "ps_ai_model")
    }

    private func loadSettings() {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: "ps_glasses_format"),
           let fmt  = GlassesFormat(rawValue: raw)    { glassesFormat = fmt }
        if let raw = ud.string(forKey: "ps_voice_mode"),
           let vm   = VoiceMode(rawValue: raw)         { voiceMode    = vm  }
        if let raw = ud.string(forKey: "ps_ai_provider"),
           let prov = AICommandManager.AIProvider(rawValue: raw) { aiProvider = prov }
        aiApiKey        = ud.string(forKey: "ps_ai_api_key") ?? ""
        aiModel         = ud.string(forKey: "ps_ai_model")   ?? ""
        streamToGlasses = ud.object(forKey: "ps_stream_glasses") as? Bool ?? true
        snapshotMode    = ud.object(forKey: "ps_snapshot_mode")  as? Bool ?? false
        truncateWidth   = ud.integer(forKey: "ps_truncate_width").nonZero ?? 55
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
