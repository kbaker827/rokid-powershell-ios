import SwiftUI

struct TerminalView: View {
    @EnvironmentObject private var vm: TerminalViewModel
    @FocusState private var inputFocused: Bool
    @State  private var showQuickCommands = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionBanner
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
                ToolbarItem(placement: .navigationBarLeading)  { statusDots }
                ToolbarItem(placement: .navigationBarTrailing) { clearButton }
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
            Text(vm.isPCConnected ? "PC connected on :8102" : "Waiting for PC on :8102…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(vm.isPCConnected ? .green : Color(white: 0.5))

            Spacer()

            Circle()
                .fill(vm.glassesServer.isRunning ? Color.cyan : Color(white: 0.3))
                .frame(width: 7, height: 7)
            Text("Glasses :8101 (\(vm.glassesServer.clientCount))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.cyan.opacity(vm.glassesServer.isRunning ? 1 : 0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(white: 0.06))
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

    // MARK: - Toolbar

    private var statusDots: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.streamToGlasses ? "eyeglasses" : "eyeglasses.slash")
                .font(.caption)
                .foregroundStyle(vm.streamToGlasses ? .cyan : Color(white: 0.4))
        }
    }

    private var clearButton: some View {
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
