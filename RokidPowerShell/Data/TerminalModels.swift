import Foundation
import SwiftUI

// MARK: - Terminal line

struct TerminalLine: Identifiable, Equatable {
    let id: UUID
    let text: String
    let type: LineType
    let timestamp: Date

    init(text: String, type: LineType) {
        self.id        = UUID()
        self.text      = text
        self.type      = type
        self.timestamp = Date()
    }

    enum LineType {
        case output      // stdout — white
        case error       // stderr — red
        case prompt      // PS prompt — cyan
        case command     // typed command — yellow
        case system      // app messages — gray
        case voice       // voice transcript — magenta
        case aiThinking  // AI is generating — purple
        case aiCommand   // AI-generated PS command — green
    }

    var color: Color {
        switch type {
        case .output:     return Color(.lightGray)
        case .error:      return .red
        case .prompt:     return Color(red: 0.3, green: 0.9, blue: 1.0)
        case .command:    return .yellow
        case .system:     return Color(.darkGray)
        case .voice:      return Color(red: 1.0, green: 0.4, blue: 0.9)
        case .aiThinking: return Color(red: 0.7, green: 0.5, blue: 1.0)
        case .aiCommand:  return Color(red: 0.3, green: 1.0, blue: 0.5)
        }
    }

    /// Stripped of ANSI escape codes for clean display
    var cleanText: String { text.strippingANSI }

    /// Truncated to N chars for glasses display
    func truncated(to length: Int = 55) -> String {
        let clean = cleanText
        if clean.count <= length { return clean }
        return String(clean.prefix(length - 1)) + "…"
    }
}

// MARK: - Glasses display format

enum GlassesFormat: String, CaseIterable, Identifiable {
    case lastLines  = "lastLines"
    case outputOnly = "outputOnly"
    case minimal    = "minimal"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lastLines:  return "Last lines"
        case .outputOnly: return "Output only"
        case .minimal:    return "Prompt + last line"
        }
    }
    var description: String {
        switch self {
        case .lastLines:  return "Streams last 3 lines (prompt + output)"
        case .outputOnly: return "Output/error lines only, no prompts"
        case .minimal:    return "Current prompt + most recent output line"
        }
    }
}

// MARK: - Voice mode

enum VoiceMode: String, CaseIterable, Identifiable {
    case direct = "direct"
    case ai     = "ai"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .direct: return "Direct"
        case .ai:     return "AI Assist"
        }
    }
    var description: String {
        switch self {
        case .direct: return "Speak a command → runs immediately on the PC"
        case .ai:     return "Speak anything → AI converts to PowerShell → runs on the PC"
        }
    }
    var icon: String {
        switch self {
        case .direct: return "mic.circle.fill"
        case .ai:     return "sparkles"
        }
    }
}

// MARK: - PC bridge wire protocol
//
// PC → iPhone lines:
//   O:<text>   stdout output
//   E:<text>   stderr / error
//   P:<text>   PS prompt  (e.g.  P:PS C:\Users\user>)
//   S:<text>   system / info message
//   CLR:       clear screen
//
// iPhone → PC lines:
//   CMD:<text>\n    execute a command in the PS session

struct PSProtocol {
    static func parse(_ raw: String) -> TerminalLine? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("O:")  { return TerminalLine(text: String(s.dropFirst(2)), type: .output)  }
        if s.hasPrefix("E:")  { return TerminalLine(text: String(s.dropFirst(2)), type: .error)   }
        if s.hasPrefix("P:")  { return TerminalLine(text: String(s.dropFirst(2)), type: .prompt)  }
        if s.hasPrefix("S:")  { return TerminalLine(text: String(s.dropFirst(2)), type: .system)  }
        if s == "CLR:"        { return nil }  // caller handles clear
        // Bare text → treat as output
        if !s.isEmpty         { return TerminalLine(text: s, type: .output) }
        return nil
    }

    static func isClear(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines) == "CLR:"
    }

    static func command(_ text: String) -> Data {
        Data(("CMD:\(text)\n").utf8)
    }
}

// MARK: - ANSI stripping

private extension String {
    var strippingANSI: String {
        // Remove ESC[ ... m sequences and other common escape sequences
        replacingOccurrences(of: #"\x1B\[[0-9;]*[mGKHF]"#,
                             with: "",
                             options: .regularExpression)
        .replacingOccurrences(of: #"\x1B[()][AB012]"#,
                              with: "",
                              options: .regularExpression)
    }
}
