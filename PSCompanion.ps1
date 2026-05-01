<#
.SYNOPSIS
    Rokid PowerShell Companion — streams your PowerShell session to the iPhone (and on to Rokid AR glasses).

.DESCRIPTION
    Connects to the Rokid PowerShell iOS app on your iPhone via TCP :8102.
    Sends all stdout/stderr output prefixed with the protocol codes.
    Receives commands typed on the iPhone and executes them locally.

.PARAMETER iPhoneIP
    IP address of your iPhone on the local network.
    Find it in the app under Settings tab.

.PARAMETER Port
    TCP port to connect to. Default: 8102

.EXAMPLE
    .\PSCompanion.ps1 -iPhoneIP 192.168.1.42

.EXAMPLE
    .\PSCompanion.ps1 -iPhoneIP 192.168.1.42 -Port 8102
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$iPhoneIP,

    [int]$Port = 8102
)

# ── Protocol helpers ──────────────────────────────────────────────────────────
function Send-Line {
    param([string]$Prefix, [string]$Text)
    $line = "$Prefix$Text`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
    try { $writer.Write($bytes, 0, $bytes.Length); $writer.Flush() }
    catch { }
}

function Send-Output  { param([string]$t) Send-Line "O:" $t }
function Send-Error   { param([string]$t) Send-Line "E:" $t }
function Send-Prompt  { param([string]$t) Send-Line "P:" $t }
function Send-System  { param([string]$t) Send-Line "S:" $t }
function Send-Clear   { Send-Line "CLR:" "" }

# ── Strip ANSI escape codes ───────────────────────────────────────────────────
function Strip-ANSI {
    param([string]$Text)
    return [regex]::Replace($Text, '\x1B\[[0-9;]*[mGKHFJA-Z]', '')
}

# ── Connect to iPhone ─────────────────────────────────────────────────────────
Write-Host "Rokid PowerShell Companion" -ForegroundColor Cyan
Write-Host "Connecting to iPhone at $iPhoneIP`:$Port..." -ForegroundColor Gray

$connected = $false
$retries   = 0

while (-not $connected) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($iPhoneIP, $Port)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.BinaryWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $connected = $true
        Write-Host "Connected! iPhone is now mirroring your PowerShell session to the Rokid glasses." -ForegroundColor Green
    }
    catch {
        $retries++
        if ($retries -ge 10) {
            Write-Host "Could not connect after 10 tries. Is the iOS app running on $iPhoneIP`:$Port?" -ForegroundColor Red
            exit 1
        }
        Write-Host "Retrying ($retries/10)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

# Send system info on connect
Send-System "Connected: $env:COMPUTERNAME  $(Get-Date -Format 'HH:mm')"
Send-System "PS $($PSVersionTable.PSVersion)  $([System.Environment]::OSVersion.VersionString)"

# ── Command reader loop (background job) ─────────────────────────────────────
# We use a shared [System.Collections.Concurrent.ConcurrentQueue] to pass
# commands from the reader thread to the main execution thread.

$commandQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

$readerJob = [System.Threading.Thread]::new({
    param($r, $q)
    try {
        while ($true) {
            $line = $r.ReadLine()
            if ($null -eq $line) { break }
            if ($line.StartsWith("CMD:")) {
                $cmd = $line.Substring(4).Trim()
                if ($cmd.Length -gt 0) { $q.Enqueue($cmd) }
            }
        }
    } catch { }
})
$readerJob.IsBackground = $true
$readerJob.Start($reader, $commandQueue)

# ── Main execution loop ───────────────────────────────────────────────────────
Write-Host "Session active. Type commands on your iPhone or here. Ctrl+C to quit." -ForegroundColor Cyan

try {
    while ($true) {
        # Show prompt
        $location = (Get-Location).Path
        $promptStr = "PS $location>"
        Send-Prompt $promptStr
        Write-Host $promptStr -NoNewline -ForegroundColor Cyan

        # Wait for a command from either the iPhone or local stdin
        $cmd = $null
        while ($null -eq $cmd) {
            # Check iPhone command queue
            $dequeued = ""
            if ($commandQueue.TryDequeue([ref]$dequeued)) {
                $cmd = $dequeued
                Write-Host " [iPhone] $cmd" -ForegroundColor Yellow
                # Echo the command
                Send-Output "> $cmd"
            }
            # Check if local stdin has input (non-blocking on Windows)
            elseif ([Console]::KeyAvailable) {
                $cmd = Read-Host
            }
            else {
                Start-Sleep -Milliseconds 50
            }
        }

        if ([string]::IsNullOrWhiteSpace($cmd)) { continue }

        # Handle clear specially
        if ($cmd -eq "cls" -or $cmd -eq "clear" -or $cmd -eq "Clear-Host") {
            Clear-Host
            Send-Clear
            continue
        }

        # Execute and capture
        $sb = [scriptblock]::Create($cmd)
        try {
            $results = & $sb 2>&1
            foreach ($item in $results) {
                $text = Strip-ANSI ($item | Out-String -Width 200).TrimEnd()
                if ($text.Trim().Length -eq 0) { continue }
                foreach ($line in $text -split "`n") {
                    $l = $line.TrimEnd()
                    if ($l.Length -eq 0) { continue }
                    if ($item -is [System.Management.Automation.ErrorRecord]) {
                        Send-Error $l
                        Write-Host $l -ForegroundColor Red
                    } else {
                        Send-Output $l
                        Write-Host $l
                    }
                }
            }
        }
        catch {
            $errText = Strip-ANSI $_.Exception.Message
            Send-Error $errText
            Write-Host $errText -ForegroundColor Red
        }
    }
}
finally {
    Write-Host "`nDisconnecting…" -ForegroundColor Gray
    Send-System "Session ended"
    try { $stream.Close(); $client.Close() } catch { }
}
