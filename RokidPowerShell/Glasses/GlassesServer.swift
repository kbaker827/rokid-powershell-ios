// GlassesServer.swift — updated to use Rokid AI glasses SDK
// Previously used raw TCP sockets; now communicates over Bluetooth via RokidSDK.
//
// Setup:
//   1. pod install  (Podfile already updated)
//   2. Get credentials from https://account.rokid.com/#/setting/prove
//   3. Fill in appKey / appSecret / accessKey below

import Foundation
import RokidSDK

// ── Credentials ───────────────────────────────────────────────────────────────
private let kAppKey    = "YOUR_APP_KEY"
private let kAppSecret = "YOUR_APP_SECRET"
private let kAccessKey = "YOUR_ACCESS_KEY"

// ─────────────────────────────────────────────────────────────────────────────
@MainActor
final class GlassesServer: ObservableObject {

    // Published state
    @Published var isRunning:    Bool = false
    @Published var isConnected:  Bool = false
    @Published var clientCount:  Int  = 0     // kept for UI compatibility; always 0 or 1
    @Published var nearbyDevices: [RKDevice] = []

    // Inbound callbacks (same contract as the original TCP version)
    var onMicTrigger:      (() -> Void)?
    var onGlassesCommand:  ((String) -> Void)?

    // Active paired device
    private var activeDevice: RKDevice?

    // ── SDK init ──────────────────────────────────────────────────────────────
    init() {
        RokidMobileSDK.shared.initSDK(
            appKey:    kAppKey,
            appSecret: kAppSecret,
            accessKey: kAccessKey
        ) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error { print("[Rokid] init error: \(error)") }
                else { self?.loadPairedDevices() }
            }
        }
        RokidMobileSDK.binder.addObserver(observer: self)
    }

    // ── Device discovery ──────────────────────────────────────────────────────
    func loadPairedDevices() {
        RokidMobileSDK.device.queryDeviceList { [weak self] _, devices in
            Task { @MainActor [weak self] in
                self?.nearbyDevices = devices ?? []
                // Auto-connect to first device if only one is paired
                if let first = devices?.first { self?.connectDevice(first) }
            }
        }
    }

    func connectDevice(_ device: RKDevice) {
        activeDevice = device
        isConnected  = true
        clientCount  = 1
        isRunning    = true
        print("[Rokid] Connected to \(device.deviceName ?? "glasses")")
    }

    func disconnectDevice() {
        activeDevice = nil
        isConnected  = false
        clientCount  = 0
        isRunning    = false
    }

    // ── Public API (original method signatures preserved) ─────────────────────
    func start() {
        loadPairedDevices()
    }

    func stop() {
        activeDevice = nil
        isConnected = false
    }

    func broadcastLine(_ line: TerminalLine, truncateAt: Int = 55) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "line", text: String(describing: line), to: dev)
    }

    func broadcastSnapshot(_ lines: [TerminalLine], format: GlassesFormat) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "snapshot", text: String(describing: format), to: dev)
    }

    func broadcastClear() {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "clear", text: "", to: dev)
    }

    func broadcastStatus(_ msg: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "status", text: String(describing: msg), to: dev)
    }

    func broadcastListening(_ active: Bool) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "voiceState", text: "\(name)", to: dev)
    }

    func broadcastVoiceTranscript(_ text: String, isFinal: Bool) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "voiceState", text: "\(name)", to: dev)
    }

    func broadcastAIThinking(_ text: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "aithinking", text: String(describing: text), to: dev)
    }

    func broadcastAICommand(_ cmd: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "aicommand", text: String(describing: cmd), to: dev)
    }
}

// ── Receive voice commands FROM the glasses ───────────────────────────────────
extension GlassesServer: SDKBinderObserver {
    nonisolated func onAsrResult(_ asr: String, device: RKDevice) {
        let cmd = asr.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            if cmd.lowercased().hasPrefix("run ") {
                self.onGlassesCommand?(String(cmd.dropFirst(4)))
            } else if cmd.lowercased().hasPrefix("ai ") {
                self.onRemoteQuery?(String(cmd.dropFirst(3)))
            } else if cmd.lowercased() == "mic" {
                self.onMicTrigger?()
            } else {
                self.onGlassesCommand?(cmd)
            }
        }
    }
}
