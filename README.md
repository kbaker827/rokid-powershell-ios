# Rokid PowerShell HUD

Live-stream your Windows PowerShell session to Rokid AR glasses — via your iPhone as a wireless bridge.

```
Windows PC  ──TCP :8102──▶  iPhone App  ──TCP :8101──▶  Rokid Glasses
             PSCompanion.ps1              (this app)
             (bidirectional)              (bidirectional)
```

## How It Works

1. **PSCompanion.ps1** runs on your Windows PC and connects outbound to the iPhone on port **8102**.
2. The iPhone app accepts that connection and acts as a relay, forwarding terminal output to the Rokid glasses on port **8101**.
3. Commands typed on the glasses (or in the iPhone app) are sent back to the PC as `CMD:` messages and executed in real time.

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

---

## Wire Protocol

### PC → iPhone (port 8102)

| Prefix | Meaning        | Example                    |
|--------|----------------|----------------------------|
| `O:`   | stdout line    | `O:Hello, World!`          |
| `E:`   | stderr / error | `E:Cannot find path...`    |
| `P:`   | prompt         | `P:PS C:\Users\you>`       |
| `S:`   | system message | `S:Connected: MYPC  14:32` |
| `CLR:` | clear screen   | `CLR:`                     |

### iPhone → PC (port 8102)

| Prefix | Meaning       | Example              |
|--------|---------------|----------------------|
| `CMD:` | run a command | `CMD:Get-Process\n`  |

### iPhone → Glasses (port 8101)

JSON packets, newline-delimited:

```json
{"type":"line","prefix":"O","text":"Directory of C:\\"}
{"type":"snapshot","lines":["PS C:\\>","Get-Date","Wednesday, April 30, 2026"]}
{"type":"clear"}
{"type":"status","text":"PC connected"}
```

---

## Display Formats (Glasses)

| Format       | Description                                      |
|--------------|--------------------------------------------------|
| **Last Lines** | Most recent 3 lines regardless of type         |
| **Output Only** | Last 3 stdout/error lines (skips prompts)    |
| **Minimal**  | Current prompt + last output line (2 lines max)  |

Switch formats in **Settings → Glasses Display → Format**.

---

## Quick Commands

Tap the lightning bolt in the Terminal tab for one-tap presets:

- `Get-Process` — running processes
- `Get-Service` — Windows services
- `Get-Date` — current date/time
- `whoami` — current user
- `pwd` — current directory
- `ls` — directory listing
- `ipconfig` — network config
- `Get-EventLog -Newest 5 -LogName System` — recent system events

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iPhone    | iOS 17+, same Wi-Fi as PC |
| Xcode     | 15.0+ |
| Windows   | PowerShell 7+ (pwsh) recommended; Windows PowerShell 5.1 also works |
| Glasses   | Rokid AR glasses on same Wi-Fi as iPhone |

---

## Ports

| Port | Direction | Purpose                       |
|------|-----------|-------------------------------|
| 8102 | PC → iPhone | PSCompanion connects here  |
| 8101 | Glasses → iPhone | Glasses connect here    |

Both ports listen on `0.0.0.0` (all interfaces). Ensure your iPhone's firewall/hotspot allows inbound connections on these ports.

---

## Project Structure

```
rokid-powershell-ios/
├── PSCompanion.ps1                      ← Windows companion script
└── RokidPowerShell/
    ├── App/
    │   ├── RokidPowerShellApp.swift     ← @main entry point
    │   └── Info.plist
    ├── Data/
    │   └── TerminalModels.swift         ← TerminalLine, GlassesFormat, PSProtocol
    ├── Service/
    │   └── PCBridgeServer.swift         ← NWListener :8102, PC TCP server
    ├── Glasses/
    │   └── GlassesServer.swift          ← NWListener :8101, glasses TCP server
    ├── ViewModel/
    │   └── TerminalViewModel.swift      ← ObservableObject, bridges PC ↔ glasses
    └── UI/
        ├── ContentView.swift            ← TabView root
        ├── TerminalView.swift           ← Dark terminal display + command input
        └── SettingsView.swift           ← IP display, connection status, toggles
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
| **rokid-powershell-ios** | **PowerShell** | **:8101/:8102** | **TCP Bridge** |
