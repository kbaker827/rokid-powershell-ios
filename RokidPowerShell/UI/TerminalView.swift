import SwiftUI

struct TerminalView: View {
    @EnvironmentObject private var vm: TerminalViewModel
    @FocusState private var inputFocused: Bool
    @State  private var showQuickCommands = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionBanner
                if !vm.voiceStatusText.isEmpty { voiceBanner }
                if vm.isAIThinking { aiThinkingBanner }
                terminalOutput
                Divider()
                inputBar
            }
            .background(Color.black)
            .navigationTitle("PowerShell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(white: 0.08), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading)  { leftTools }
                ToolbarItem(placement: .navigationBarTrailing) { rightTools }
            }
            .sheet(isPresented: $showQuickCommands) { quickCommandSheet }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Connection banner

    private var connectionBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.isPCConnected ? Color.green : Color(white: 0.3))
                .frame(width: 7, height: 7)
            Text(vm.isPCConnected ? "PC :8102" : "Waiting :8102…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(vm.isPCConnected ? .green : Color(white: 0.5))

            Spacer()

            // Voice mode badge
            Label(vm.voiceMode.displayName, systemImage: vm.voiceMode.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(vm.voiceMode == .ai ? Color(red: 0.7, green: 0.5, blue: 1.0) : .cyan)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(white: 0.15), in: Capsule())

            Spacer()

            Circle()
                .fill(vm.glassesServer.isRunning ? Color.cyan : Color(white: 0.3))
                .frame(width: 7, height: 7)
            Text("Glasses (\(vm.glassesServer.clientCount))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.cyan.opacity(vm.glassesServer.isRunning ? 1 : 0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(white: 0.06))
    }

    // MARK: - Voice listening banner

    private var voiceBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.9))
                .font(.system(size: 13))
            Text(vm.voiceStatusText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 1.0))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Cancel") { vm.cancelVoice() }
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(red: 0.2, green: 0.05, blue: 0.2))
    }

    // MARK: - AI thinking banner

    private var aiThinkingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .symbolEffect(.pulse, options: .repeating)
                .foregroundStyle(Color(red: 0.7, green: 0.5, blue: 1.0))
                .font(.system(size: 13))
            Text("AI converting to PowerShell…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(red: 0.8, green: 0.7, blue: 1.0))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(red: 0.1, green: 0.05, blue: 0.2))
    }

    // MARK: - Terminal output

    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(vm.lines) { line in
                        Text(line.cleanText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(line.color)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Color.black)
            .onChange(of: vm.lines.count) { _, _ in
                withAnimation(.none) { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Prompt indicator
            Text("PS>")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .padding(.leading, 8)

            // Command field
            TextField("Enter command…", text: $vm.draft)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                .focused($inputFocused)
                .onSubmit { vm.sendCommand() }
                .tint(.cyan)

            // Mic button
            Button {
                vm.toggleVoice()
                inputFocused = false
            } label: {
                ZStack {
                    if vm.isListening {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.3, blue: 0.9).opacity(0.25))
                            .frame(width: 34, height: 34)
                            .scaleEffect(vm.isListening ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                       value: vm.isListening)
                    }
                    Image(systemName: vm.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 17))
                        .foregroundStyle(vm.isListening
                            ? Color(red: 1.0, green: 0.3, blue: 0.9)
                            : (vm.voiceMode == .ai
                                ? Color(red: 0.7, green: 0.5, blue: 1.0)
                                : .cyan.opacity(0.8)))
                }
                .frame(width: 34, height: 34)
            }
            .disabled(vm.isAIThinking)

            // Quick commands
            Button {
                showQuickCommands = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16))
                    .foregroundStyle(.cyan.opacity(0.8))
            }

            // Send
            Button {
                vm.sendCommand()
                inputFocused = true
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(vm.draft.isEmpty ? Color(white: 0.3) : .cyan)
            }
            .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .background(Color(white: 0.1))
    }

    // MARK: - Quick commands sheet

    private var quickCommandSheet: some View {
        NavigationStack {
            List {
                Section("Quick Commands") {
                    ForEach(vm.quickCommands, id: \.self) { cmd in
                        Button {
                            showQuickCommands = false
                            vm.sendCommand(cmd)
                        } label: {
                            Text(cmd)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                    }
                }

                Section("Voice Mode") {
                    ForEach(VoiceMode.allCases) { mode in
                        Button {
                            showQuickCommands = false
                            vm.setVoiceMode(mode)
                        } label: {
                            HStack {
                                Label(mode.displayName, systemImage: mode.icon)
                                    .foregroundStyle(mode == .ai
                                                     ? Color(red: 0.7, green: 0.5, blue: 1.0)
                                                     : .cyan)
                                Spacer()
                                if vm.voiceMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quick Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showQuickCommands = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar items

    private var leftTools: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.streamToGlasses ? "eyeglasses" : "eyeglasses.slash")
                .font(.caption)
                .foregroundStyle(vm.streamToGlasses ? .cyan : Color(white: 0.4))

            if vm.isAIThinking {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.7, green: 0.5, blue: 1.0))
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
    }

    private var rightTools: some View {
        Button {
            vm.clearTerminal()
        } label: {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(Color(white: 0.6))
        }
        .disabled(vm.lines.isEmpty)
    }
}
