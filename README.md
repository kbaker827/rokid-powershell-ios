# Rokid PowerShell HUD



> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

Live-stream your Windows PowerShell session to Rokid AR glasses — via your iPhone as a wireless bridge. Speak commands hands-free, or let AI convert plain English into PowerShell for you.

```
Windows PC  ──TCP :8102──▶  iPhone App  ──Bluetooth/RokidSDK──▶ Rokid Glasses
             PSCompanion.ps1              (this app)
             (bidirectional)              (bidirectional)

                 ☝ also: mic on iPhone or glasses-triggered voice
                          ↓
                     SFSpeechRecognizer
                          ↓
                  Direct mode → CMD sent to PC
                  AI mode     → OpenAI / Claude → PowerShell → PC
```

---

## Features

- **Live terminal mirror** — every stdout/stderr/prompt line streams to the glasses in real time
- **Type commands** on the iPhone or from the glasses
- **Voice commands (Direct mode)** — tap the mic, speak a PowerShell command, it runs
- **AI Assist mode** — speak plain English ("show me what's eating memory"), AI converts it to PowerShell, shows the generated command on the glasses, then runs it
- **Glasses-triggered mic** — glasses can send a JSON packet to start/stop iPhone listening remotely
- **Safety net** — AI automatically appends `-WhatIf` to destructive commands before running
- **Snapshot or streaming** display modes, 3 line formats, adjustable truncation width

---

## SDK Setup

The glasses now connect over **Bluetooth via the Rokid AI glasses SDK** — no Wi-Fi port or TCP server needed.

The only thing left for each app is filling in the three credential constants (`kAppKey`, `kAppSecret`, `kAccessKey`) from [account.rokid.com/#/setting/prove](https://account.rokid.com/#/setting/prove), then running `pod install`.

1. **Get credentials** at <https://account.rokid.com/#/setting/prove> and paste them into the glasses Swift file:
   ```swift
   private let kAppKey    = "YOUR_APP_KEY"
   private let kAppSecret = "YOUR_APP_SECRET"
   private let kAccessKey = "YOUR_ACCESS_KEY"
   ```

2. **Install CocoaPods dependencies** from the repo root:
   ```bash
   pod install
   open *.xcworkspace   # always open the .xcworkspace, not .xcodeproj
   ```

3. *(Glasses now connect automatically over Bluetooth — no TCP port needed.)*

## Quick Start

### 1. Install the iOS app

Open `RokidPowerShell.xcodeproj` in Xcode 15+, select your iPhone as the target, and run.

### 2. Find your iPhone IP

Open the app → **Settings** tab → copy the iPhone IP shown at the top.

### 3. Run the companion script on your PC

```powershell
.\PSCompanion.ps1 -iPhoneIP 192.168.1.42
```

The script is in the repo root. Once connected you'll see:

```
Rokid PowerShell Companion
Connecting to iPhone at 192.168.1.42:8102...
Connected! iPhone is now mirroring your PowerShell session to the Rokid glasses.
Session active. Type commands on your iPhone or here. Ctrl+C to quit.
```

### 4. Put on your glasses

The Rokid glasses connect to the iPhone on **:8101** and receive the terminal stream automatically.

### 5. (Optional) Set up AI Assist

Go to **Settings → AI Assist**, pick a provider, and paste your API key:

| Provider | Default model | Where to get a key |
|----------|---------------|-------------------|
| OpenAI   | `gpt-4o-mini` | platform.openai.com |
| Claude   | `claude-3-5-haiku-20241022` | console.anthropic.com |

Leave the model field blank to use the default, or type e.g. `gpt-4o` to override.

---

## Voice Commands

### From the iPhone

Tap the **🎤 mic button** in the Terminal tab input bar. A pink pulsing banner appears while the app is listening. Speech stops automatically after **1.8 seconds of silence**.

### From the Glasses (remote trigger)

The glasses can send JSON messages over the TCP connection to control the iPhone mic:

```json
{"type":"mic"}
```
→ Toggles iPhone microphone on/off (starts or stops listening)

```json
{"type":"cmd","text":"Get-Process"}
```
→ Runs a command directly on the PC without going through voice

```json
{"type":"ai","text":"show me what's using the most CPU"}
```
→ Sends text to AI mode — converts to PowerShell then runs on PC

---

## Voice Modes

Switch the mode in **Settings → Voice Commands** or via the quick-command sheet (list icon in the input bar).

### Direct mode (`mic.circle.fill`)

```
You speak → transcribed as-is → CMD sent to PC → output appears on glasses
```

Useful when you already know PowerShell syntax and just want hands-free input.

### AI Assist mode (`sparkles`)

```
You speak plain English
    → iPhone transcribes
    → AI (OpenAI or Claude) converts to PowerShell
    → Generated command shown on glasses in green
    → Command runs on PC
    → Output streams to glasses
```

Examples of what you can say:

| What you say | What runs on the PC |
|---|---|
| *"show me the top 10 processes by CPU"* | `Get-Process \| Sort-Object CPU -Descending \| Select-Object -First 10` |
| *"list all running services"* | `Get-Service \| Where-Object Status -eq Running` |
| *"what's my IP address"* | `Get-NetIPAddress \| Where-Object AddressFamily -eq IPv4` |
| *"when was this PC last rebooted"* | `(Get-CimInstance Win32_OperatingSystem).LastBootUpTime` |
| *"delete temp files"* | `Remove-Item $env:TEMP\* -Recurse -Force -WhatIf` ← -WhatIf added automatically |

---

## Wire Protocol

### PC → iPhone (Bluetooth/RokidSDK)

| Prefix | Meaning        | Example                    |
|--------|----------------|----------------------------|
| `O:`   | stdout line    | `O:Hello, World!`          |
| `E:`   | stderr / error | `E:Cannot find path...`    |
| `P:`   | prompt         | `P:PS C:\Users\you>`       |
| `S:`   | system message | `S:Connected: MYPC  14:32` |
| `CLR:` | clear screen   | `CLR:`                     |

### iPhone → PC (Bluetooth/RokidSDK)

| Prefix | Meaning       | Example              |
|--------|---------------|----------------------|
| `CMD:` | run a command | `CMD:Get-Process\n`  |

### iPhone → Glasses (Bluetooth/RokidSDK)

JSON packets, newline-delimited:

```json
{"type":"output",      "text":"Directory of C:\\"}
{"type":"error",       "text":"Access denied"}
{"type":"prompt",      "text":"PS C:\\Users\\you>"}
{"type":"command",     "text":"> Get-Process"}
{"type":"system",      "text":"PC connected on :8102"}
{"type":"voice",       "text":"🎤 show me running services"}
{"type":"ai_thinking", "text":"AI thinking…"}
{"type":"ai_command",  "text":"Get-Service | Where-Object Status -eq Running"}
{"type":"voice_state", "text":"listening"}
{"type":"voice_state", "text":"idle"}
{"type":"voice_partial","text":"show me run..."}
{"type":"voice_final", "text":"show me running services"}
{"type":"terminal",    "text":"PS C:\\>\nGet-Date\nWednesday, 1 May 2026"}
{"type":"clear",       "text":""}
{"type":"status",      "text":"Streaming paused"}
```

### Glasses → iPhone (Bluetooth/RokidSDK)

```json
{"type":"mic"}
{"type":"cmd","text":"Get-Process"}
{"type":"ai","text":"show me disk space"}
```

---

## Terminal Line Colors

| Color | Type | Meaning |
|-------|------|---------|
| Light gray | Output | Normal stdout |
| Red | Error | stderr / exceptions |
| Cyan | Prompt | `PS C:\>` prompt lines |
| Yellow | Command | Commands you send |
| Dark gray | System | App status messages |
| Magenta | Voice | Voice transcript |
| Purple | AI Thinking | AI is generating a command |
| Green | AI Command | AI-generated PowerShell command |

---

## Display Formats (Glasses)

| Format | Description |
|--------|-------------|
| **Last Lines** | Most recent 3 lines regardless of type |
| **Output Only** | Last 3 stdout/error lines (skips prompts) |
| **Minimal** | Current prompt + last output line (2 lines max) |

Switch in **Settings → Glasses Display → Format**.

---

## Quick Commands

Tap the **list icon** in the Terminal tab input bar for one-tap presets and the voice mode switcher:

- `Get-Process | Select-Object -First 10`
- `Get-Service | Where-Object Status -eq Running`
- `Get-Date`
- `Get-ComputerInfo | Select-Object CsName, OsName`
- `Get-Disk`
- `Get-NetIPAddress | Where-Object AddressFamily -eq IPv4`
- `Get-EventLog -LogName System -Newest 5`
- `Clear-Host`

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iPhone | iOS 17+, same Wi-Fi as PC |
| Xcode | 15.0+ |
| Windows | PowerShell 7+ (pwsh) recommended; Windows PowerShell 5.1 also works |
| Glasses | Rokid AR glasses on same Wi-Fi as iPhone |
| AI Assist | OpenAI or Anthropic API key (optional) |
| CocoaPods | 1.15+ — run `pod install` after cloning |

**Permissions required on iPhone:**
- Microphone — for voice commands
- Speech Recognition — for transcription (processed on-device or by Apple)
- Local Network — for TCP bridge to PC and glasses

---

## Ports

| Port | Direction | Purpose |
|------|-----------|---------|
| 8102 | PC → iPhone | PSCompanion.ps1 connects here |
| 8101 | Glasses → iPhone | Glasses connect here (bidirectional) |

Both ports listen on `0.0.0.0` (all interfaces). Ensure your iPhone's firewall/hotspot allows inbound connections on these ports.

---

## Project Structure

```
rokid-powershell-ios/
├── PSCompanion.ps1                      ← Windows companion script
└── RokidPowerShell/
    ├── App/
    │   ├── RokidPowerShellApp.swift     ← @main entry point
    │   └── Info.plist                   ← mic + speech + network permissions
    ├── Data/
    │   └── TerminalModels.swift         ← TerminalLine, GlassesFormat, VoiceMode, PSProtocol
    ├── Service/
    │   ├── PCBridgeServer.swift         ← NWListener :8102, PC TCP server
    │   ├── SpeechManager.swift          ← SFSpeechRecognizer + AVAudioEngine, silence detection
    │   └── AICommandManager.swift       ← Natural language → PowerShell via OpenAI or Claude
    ├── Glasses/
    │   └── GlassesServer.swift          ← NWListener :8101, bidirectional glasses TCP server
    ├── ViewModel/
    │   └── TerminalViewModel.swift      ← Wires PC bridge, glasses, speech, and AI together
    └── UI/
        ├── ContentView.swift            ← TabView root
        ├── TerminalView.swift           ← Dark terminal, mic button, voice/AI banners
        └── SettingsView.swift           ← IP, AI key, provider, voice mode, display settings
```

---

## Part of the Rokid iOS Bridge Suite

| App | Source | TCP Port | Data Source |
|-----|--------|----------|-------------|
| [rokid-claude-ios](https://github.com/kbaker827/rokid-claude-ios) | Claude AI | :8095 | Anthropic API |
| [rokid-chatgpt-ios](https://github.com/kbaker827/rokid-chatgpt-ios) | ChatGPT | :8096 | OpenAI API |
| [rokid-lansweeper-ios](https://github.com/kbaker827/rokid-lansweeper-ios) | Lansweeper | :8097 | GraphQL API |
| [rokid-teams-ios](https://github.com/kbaker827/rokid-teams-ios) | MS Teams | :8098 | Graph API |
| [rokid-outlook-ios](https://github.com/kbaker827/rokid-outlook-ios) | Outlook | :8099 | Graph API |
| [rokid-compass-ios](https://github.com/kbaker827/rokid-compass-ios) | Compass | :8100 | CoreLocation |
| **rokid-powershell-ios** | **PowerShell** | **:8101/:8102** | **TCP Bridge + Voice + AI** |
