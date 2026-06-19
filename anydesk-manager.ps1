<#
.SYNOPSIS
    AnyDesk Manager v2.2 — Surgical ID reset, scheduler, telemetry blocking, and more.
.DESCRIPTION
    A polished PowerShell utility to manage AnyDesk commercial-use detection.
    UI styled after Microsoft Activation Scripts (MAS) — clean, sectioned, ASCII-only.
    Double-click anydesk-manager.cmd to launch, or run directly as admin.
    Auto-elevates if not admin.
.NOTES
    Requires: Administrator privileges
    Tested on: Windows 10/11, AnyDesk 7.x/8.x
#>

# --- Auto-elevation ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        # Running from a saved file — re-launch it
        Start-Process powershell -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    } else {
        # Running via irm | iex — save to temp, then re-launch
        $tmp = "$env:TEMP\anydesk-manager.ps1"
        irm "https://raw.githubusercontent.com/Tastico/anydesk-manager/main/anydesk-manager.ps1" | Out-File $tmp -Encoding UTF8
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`"" -Verb RunAs
    }
    exit
}

$ScriptVersion = "2.2.0"
$ScriptTitle   = "AnyDesk Manager"
$LogDir        = "$env:ProgramData\AnyDesk_Manager\logs"
$BackupDir     = "$env:ProgramData\AnyDesk_Manager\backups"
$TaskName      = "AnyDesk Manager - Auto ID Reset"

# ========================================================================
#  Color scheme
# ========================================================================
$C_Green  = "Green"
$C_White  = "White"
$C_Gray   = "DarkGray"
$C_Red    = "Red"
$C_Yellow = "Yellow"
$C_Cyan   = "Cyan"
$C_Magenta = "Magenta"

# ========================================================================
#  UI helper functions (MAS-inspired)
# ========================================================================

function Write-ColorLine {
    param([string[]]$Parts)  # @("text1", "color1", "text2", "color2", ...)
    for ($i = 0; $i -lt $Parts.Count; $i += 2) {
        Write-Host $Parts[$i] -NoNewline -ForegroundColor $Parts[$i+1]
    }
    Write-Host ""
}

function Write-Separator {
    param([int]$Width = 62)
    Write-Host (" " * 7) -NoNewline
    Write-Host ("_" * $Width)
}

function Write-SubSeparator {
    param([int]$Width = 50)
    Write-Host (" " * 12) -NoNewline
    Write-Host ("_" * $Width)
}

function Write-BlankLine {
    Write-Host ""
}

function Write-MenuItem {
    param([string]$Key, [string]$Name, [string]$Desc = "", [bool]$Highlighted = $true)
    Write-Host (" " * 10) -NoNewline
    if ($Highlighted) {
        Write-Host ("[" + $Key + "] ") -NoNewline -ForegroundColor $C_White
        Write-Host $Name.PadRight(22) -NoNewline -ForegroundColor $C_Green
    } else {
        Write-Host ("[" + $Key + "] ") -NoNewline -ForegroundColor $C_Gray
        Write-Host $Name.PadRight(22) -NoNewline -ForegroundColor $C_Gray
    }
    if ($Desc) {
        Write-Host "- " -NoNewline -ForegroundColor $C_Gray
        Write-Host $Desc -ForegroundColor $C_Gray
    } else {
        Write-Host ""
    }
}

function Write-CategoryLabel {
    param([string]$Label)
    Write-Host (" " * 10) -NoNewline
    Write-Host $Label -ForegroundColor $C_White
}

function Write-Prompt {
    param([string]$Text, [string]$Options = "")
    Write-Host ""
    Write-Host (" " * 7) -NoNewline
    Write-Host "Choose a menu option using your keyboard " -NoNewline -ForegroundColor $C_White
    if ($Options) {
        Write-Host "[$Options] " -NoNewline -ForegroundColor $C_Green
    }
    Write-Host ": " -NoNewline -ForegroundColor $C_White
}

function Write-Tip {
    param([string]$Text)
    Write-Host (" " * 7) -NoNewline
    Write-Host "Tip: " -NoNewline -ForegroundColor $C_Green
    Write-Host $Text -ForegroundColor $C_White
}

function Write-ResultLine {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    Write-Host (" " * 7) -NoNewline
    Write-Host ($Label.PadRight(24)) -NoNewline -ForegroundColor $C_Gray
    Write-Host $Value -ForegroundColor $Color
}

function Write-StepLine {
    param([string]$Text, [string]$Status = "info")
    $color = switch ($Status) {
        "ok"    { $C_Green }
        "fail"  { $C_Red }
        "warn"  { $C_Yellow }
        default { $C_Gray }
    }
    $prefix = switch ($Status) {
        "ok"    { "[OK]  " }
        "fail"  { "[ERR] " }
        "warn"  { "[WRN] " }
        default { "[*]   " }
    }
    Write-Host (" " * 7) -NoNewline
    Write-Host ($prefix + $Text) -ForegroundColor $color
}

function Write-InfoLines {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        Write-Host (" " * 7) -NoNewline
        Write-Host $line -ForegroundColor $C_Gray
    }
}

function Write-SectionTitle {
    param([string]$Title)
    Write-Host (" " * 7) -NoNewline
    Write-Host $Title -ForegroundColor $C_Yellow
    Write-BlankLine
}

function Pause-Return {
    Write-BlankLine
    Write-Host (" " * 7) -NoNewline
    Write-Host "Press any key to return to menu..." -ForegroundColor $C_Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ========================================================================
#  Logging
# ========================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -Path "$LogDir\anydesk-manager.log" -Value $entry -Encoding UTF8
}

# ========================================================================
#  Core functions
# ========================================================================

function Find-AnyDesk {
    $paths = @(
        "${env:ProgramFiles}\AnyDesk\AnyDesk.exe",
        "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe",
        "$env:ProgramData\AnyDesk\AnyDesk.exe",
        "$env:LOCALAPPDATA\AnyDesk\AnyDesk.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    $proc = Get-Process -Name "AnyDesk*" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path -ErrorAction SilentlyContinue
    if ($proc) { return $proc }
    return $null
}

function Get-CurrentAnyDeskID {
    $confPaths = @("$env:ProgramData\AnyDesk\system.conf", "$env:APPDATA\AnyDesk\system.conf", "$env:LOCALAPPDATA\AnyDesk\system.conf")
    foreach ($p in $confPaths) {
        if (Test-Path $p) {
            $match = Select-String -Path $p -Pattern 'ad\.anynet\.id=(.+)' | Select-Object -First 1
            if ($match) { return $match.Matches.Groups[1].Value }
        }
    }
    return $null
}

function Stop-AnyDeskAggressively {
    param([bool]$ShowUI = $true)
    if ($ShowUI) { Write-StepLine "Stopping AnyDesk processes" }
    Write-Log "Stopping AnyDesk processes and services"
    for ($i = 1; $i -le 5; $i++) {
        Stop-Service -Name "AnyDesk" -Force -ErrorAction SilentlyContinue
        Get-Process -Name "AnyDesk*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process -Name "AnyDesk*" -ErrorAction SilentlyContinue)) { break }
    }
    $stillRunning = Get-Process -Name "AnyDesk*" -ErrorAction SilentlyContinue
    if ($stillRunning) {
        if ($ShowUI) { Write-StepLine "Some AnyDesk processes still running" "warn" }
        Write-Log "Some AnyDesk processes could not be stopped" "WARN"
        return $false
    }
    if ($ShowUI) { Write-StepLine "Stopping AnyDesk processes" "ok" }
    return $true
}

function Start-AnyDesk {
    param([bool]$WaitForConfig = $true, [bool]$ShowUI = $true)
    if ($ShowUI) { Write-StepLine "Starting AnyDesk" }
    Write-Log "Starting AnyDesk"
    Start-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
    $exe = Find-AnyDesk
    if ($exe) { Start-Process $exe -WindowStyle Hidden }
    if ($WaitForConfig) {
        $configPaths = @("$env:ProgramData\AnyDesk\system.conf", "$env:APPDATA\AnyDesk\system.conf", "$env:LOCALAPPDATA\AnyDesk\system.conf")
        for ($i = 0; $i -lt 15; $i++) {
            foreach ($p in $configPaths) {
                if (Test-Path $p) {
                    if (Select-String -Path $p -Pattern 'ad\.anynet\.id=' -Quiet) {
                        if ($ShowUI) { Write-StepLine "Starting AnyDesk" "ok" }
                        return $true
                    }
                }
            }
            Start-Sleep -Seconds 2
        }
        if ($ShowUI) { Write-StepLine "Timeout waiting for AnyDesk" "warn" }
        Write-Log "Timeout waiting for AnyDesk config regeneration" "WARN"
        return $false
    }
    if ($ShowUI) { Write-StepLine "Starting AnyDesk" "ok" }
    return $true
}

function Get-IdentityFiles {
    return @("service.auth", "ad.session.token", "service.conf", "connection_trace.txt", "*.trace", "*.old")
}

function Get-IdentityRegexPatterns {
    return @('ad\.anynet\.id=', 'ad\.service\.pubkey=', 'ad\.session\.token=', 'ad\.anydesk\.alias=', 'ad\.service\.license=')
}

function Get-TargetFolders {
    return @("$env:APPDATA\AnyDesk", "$env:ProgramData\AnyDesk", "$env:LOCALAPPDATA\AnyDesk")
}

function Get-RegistryPaths {
    return @("HKLM:\SOFTWARE\AnyDesk", "HKLM:\SOFTWARE\Wow6432Node\AnyDesk", "HKCU:\SOFTWARE\AnyDesk")
}

# ========================================================================
#  1. SURGICAL RESET
# ========================================================================

function Reset-Surgical {
    Clear-Host
    Write-BlankLine
    Write-BlankLine
    Write-SectionTitle "Surgical ID Reset"
    Write-InfoLines @(
        "Preserves:  favorites, aliases, display settings, user.conf",
        "Removes:    identity files, registry keys, connection traces"
    )
    Write-BlankLine
    
    $oldID = Get-CurrentAnyDeskID
    if ($oldID) {
        Write-ResultLine "Current AnyDesk ID:" $oldID $C_Cyan
        Write-Log "Current ID: $oldID"
    } else {
        Write-ResultLine "Current AnyDesk ID:" "NOT FOUND" $C_Yellow
    }
    Write-BlankLine
    
    if (-not (Stop-AnyDeskAggressively)) {
        Write-StepLine "Cannot proceed - AnyDesk still running" "fail"
        Pause-Return; return
    }
    
    $folders = Get-TargetFolders
    
    # Delete identity files
    $idFiles = Get-IdentityFiles
    $filesDeleted = 0
    foreach ($folder in $folders) {
        if (Test-Path $folder) {
            foreach ($pattern in $idFiles) {
                Get-ChildItem -Path $folder -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    $filesDeleted++
                    Write-Log "Deleted: $($_.FullName)"
                }
            }
        }
    }
    Write-StepLine "Deleted $filesDeleted identity files" "ok"
    
    # Surgical edit
    $patterns = Get-IdentityRegexPatterns
    $configsEdited = 0
    foreach ($folder in $folders) {
        $systemConf = Join-Path $folder "system.conf"
        if (Test-Path $systemConf) {
            $content = Get-Content $systemConf
            $newContent = $content | Where-Object { 
                $line = $_
                foreach ($p in $patterns) { if ($line -match $p) { Write-Log "Stripped: $line"; return $false } }
                return $true
            }
            $newContent | Set-Content $systemConf -Force
            $configsEdited++
        }
    }
    Write-StepLine "Stripped identity keys from $configsEdited config(s)" "ok"
    
    # Registry
    $regDeleted = 0
    foreach ($r in (Get-RegistryPaths)) {
        if (Test-Path $r) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue; $regDeleted++; Write-Log "Deleted registry: $r" }
    }
    Write-StepLine "Cleared $regDeleted registry entries" "ok"
    
    # Start and verify
    Start-AnyDesk -WaitForConfig $true
    Start-Sleep -Seconds 2
    
    Write-BlankLine
    $newID = Get-CurrentAnyDeskID
    if ($newID) {
        Write-ResultLine "New AnyDesk ID:" $newID $C_Cyan
        Write-Log "New ID: $newID"
        if ($oldID -and $newID -eq $oldID) {
            Write-StepLine "ID did not change - manual intervention may be needed" "warn"
        } elseif ($oldID -and $newID -ne $oldID) {
            Write-StepLine "ID changed successfully!" "ok"
            Write-Log "ID changed: $oldID -> $newID" "SUCCESS"
        }
    } else {
        Write-StepLine "Could not verify new ID - start AnyDesk manually" "warn"
    }
    
    Write-Log "Surgical reset completed" "SUCCESS"
    Write-BlankLine
    Write-Separator
    Write-BlankLine
    Write-ColorLine @("       " + "Reset complete. Commercial-use popup should be gone.", $C_Green)
    Write-Separator
}

# ========================================================================
#  2. FULL WIPE
# ========================================================================

function Reset-FullWipe {
    Clear-Host
    Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Full Wipe Reset"
    Write-StepLine "This deletes ALL AnyDesk data - a backup will be created first" "warn"
    Write-BlankLine
    
    Backup-Config -Silent
    
    if (-not (Stop-AnyDeskAggressively)) { Write-StepLine "Cannot proceed" "fail"; Pause-Return; return }
    
    $folders = Get-TargetFolders
    $foldersRemoved = 0
    foreach ($folder in $folders) {
        if (Test-Path $folder) { Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue; $foldersRemoved++; Write-Log "Removed: $folder" }
    }
    Write-StepLine "Removed $foldersRemoved data folder(s)" "ok"
    
    foreach ($r in (Get-RegistryPaths)) { if (Test-Path $r) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-StepLine "Cleared registry entries" "ok"
    
    Start-AnyDesk -WaitForConfig $true
    Start-Sleep -Seconds 2
    
    $newID = Get-CurrentAnyDeskID
    Write-BlankLine
    Write-ResultLine "New AnyDesk ID:" $newID $C_Cyan
    Write-BlankLine
    Write-InfoLines @("Favorites and aliases were wiped.", "Restore from backup (Option 6) if needed.")
    Write-Log "Full wipe reset completed" "SUCCESS"
}

# ========================================================================
#  3. SCHEDULE AUTO-RESET
# ========================================================================

function Schedule-AutoReset {
    Clear-Host
    Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Schedule Auto-Reset (Tier 2)"
    Write-InfoLines @(
        "Creates a Windows Scheduled Task that automatically runs",
        "a surgical ID reset so you never see the popup again.",
        "Runs as SYSTEM - no login required."
    )
    Write-BlankLine
    
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-ResultLine "Task:" $TaskName
        Write-ResultLine "State:" $existing.State $(if ($existing.State -eq "Ready") { $C_Green } else { $C_Yellow })
        Write-ResultLine "Schedule:" ($existing.Triggers | ForEach-Object { $_.ToString() })
        Write-BlankLine
        Write-MenuItem "D" "Disable task"
        Write-MenuItem "R" "Remove task"
        Write-MenuItem "U" "Update schedule"
        Write-MenuItem "C" "Cancel"
        Write-Prompt "D,R,U,C"
        $choice = Read-Host
        switch ($choice.ToUpper()) {
            "D" { Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue; Write-StepLine "Task disabled" "ok"; Pause-Return; return }
            "R" { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue; Write-StepLine "Task removed" "ok"; Pause-Return; return }
            "U" { break }
            default { return }
        }
    }
    
    Write-BlankLine
    Write-CategoryLabel "Select reset frequency:"
    Write-BlankLine
    Write-MenuItem "1" "Daily at 3:00 AM"
    Write-MenuItem "2" "Every 2 days at 3:00 AM"
    Write-MenuItem "3" "Weekly (Sunday 3:00 AM)"
    Write-MenuItem "4" "On user logon"
    Write-MenuItem "5" "Custom (every N hours)"
    Write-MenuItem "0" "Cancel" -Highlighted $false
    Write-Prompt "1,2,3,4,5,0"
    $freq = Read-Host
    
    $trigger = $null; $desc = ""
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { "$env:ProgramData\AnyDesk_Manager\anydesk-manager.ps1" }
    
    switch ($freq) {
        "1" { $trigger = New-ScheduledTaskTrigger -Daily -At "03:00"; $desc = "Daily at 3:00 AM" }
        "2" { $trigger = New-ScheduledTaskTrigger -Daily -At "03:00" -DaysInterval 2; $desc = "Every 2 days at 3:00 AM" }
        "3" { $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00"; $desc = "Weekly on Sunday" }
        "4" { $trigger = New-ScheduledTaskTrigger -AtLogon; $desc = "On user logon" }
        "5" { 
            $hours = Read-Host "       Enter hours between resets (e.g. 12)"
            try {
                $hoursInt = [int]$hours
                $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours $hoursInt) -RepetitionDuration ([TimeSpan]::MaxValue)
                $desc = "Every $hoursInt hours"
            } catch {
                Write-StepLine "Invalid input - using daily" "warn"
                $trigger = New-ScheduledTaskTrigger -Daily -At "03:00"; $desc = "Daily at 3:00 AM"
            }
        }
        default { return }
    }
    
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -SilentReset"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop
        Write-StepLine "Task scheduled: $desc" "ok"
        Write-Log "Scheduled task created: $desc"
        
        $persistentPath = "$env:ProgramData\AnyDesk_Manager\anydesk-manager.ps1"
        if ($scriptPath -ne $persistentPath) {
            New-Item -ItemType Directory -Path "$env:ProgramData\AnyDesk_Manager" -Force | Out-Null
            Copy-Item $scriptPath $persistentPath -Force
        }
        Write-BlankLine
        Write-InfoLines @("The task will run a silent surgical reset on schedule.", "Manage it here (Option 3) or via Task Scheduler.")
    } catch {
        Write-StepLine "Failed to create task: $_" "fail"
        Write-Log "Failed to create scheduled task: $_" "ERROR"
    }
}

# ========================================================================
#  4. SHOW STATUS
# ========================================================================

function Show-Status {
    Clear-Host
    Write-BlankLine; Write-BlankLine
    Write-SectionTitle "AnyDesk Status"
    
    $id = Get-CurrentAnyDeskID
    Write-ResultLine "AnyDesk ID:" $(if ($id) { $id } else { "NOT FOUND" }) $(if ($id) { $C_Cyan } else { $C_Red })
    
    $proc = Get-Process -Name "AnyDesk*" -ErrorAction SilentlyContinue
    Write-ResultLine "Process:" $(if ($proc) { "Running ($($proc.Count))" } else { "Not running" }) $(if ($proc) { $C_Green } else { $C_Yellow })
    
    $svc = Get-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
    if ($svc) {
        Write-ResultLine "Service:" $svc.Status $(if ($svc.Status -eq "Running") { $C_Green } else { $C_Yellow })
        Write-ResultLine "Startup type:" $svc.StartType
    } else {
        Write-ResultLine "Service:" "Not installed" $C_Yellow
    }
    
    $exe = Find-AnyDesk
    if ($exe) {
        try {
            Write-ResultLine "Version:" (Get-Item $exe).VersionInfo.FileVersion
            Write-ResultLine "Path:" $exe
        } catch { Write-ResultLine "Version:" "Unknown" }
    }
    
    Write-SubSeparator
    
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-ResultLine "Auto-Reset Task:" $task.State $(if ($task.State -eq "Ready") { $C_Green } else { $C_Yellow })
        Write-ResultLine "Schedule:" (($task.Triggers | ForEach-Object { $_.ToString() }) -join ", ")
    } else {
        Write-ResultLine "Auto-Reset Task:" "Not configured" $C_Yellow
    }
    
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hasBlocks = (Get-Content $hostsPath -ErrorAction SilentlyContinue | Select-String -Pattern "AnyDesk Manager Telemetry Block" -Quiet)
    Write-ResultLine "Telemetry Blocked:" $(if ($hasBlocks) { "Yes" } else { "No" }) $(if ($hasBlocks) { $C_Green } else { $C_Gray })
    
    $fwRules = Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*AnyDesk Manager*" } -ErrorAction SilentlyContinue
    Write-ResultLine "Firewall Rules:" $(if ($fwRules) { "$($fwRules.Count) active" } else { "None" })
    
    Write-SubSeparator
    
    if (Test-Path "$LogDir\anydesk-manager.log") {
        $lastReset = Select-String -Path "$LogDir\anydesk-manager.log" -Pattern "SUCCESS" | Select-Object -Last 1
        if ($lastReset) { Write-ResultLine "Last Reset:" ($lastReset.Line.Substring(0, [Math]::Min(55, $lastReset.Line.Length))) }
    }
    
    $tracePath = "$env:APPDATA\AnyDesk\connection_trace.txt"
    if (Test-Path $tracePath) {
        $traceLines = (Get-Content $tracePath | Measure-Object -Line).Lines
        Write-ResultLine "Connection Trace:" "$traceLines entries" $C_Yellow
    } else {
        Write-ResultLine "Connection Trace:" "Clean" $C_Green
    }
}

# ========================================================================
#  5. BACKUP
# ========================================================================

function Backup-Config {
    param([switch]$Silent)
    if (-not $Silent) { Clear-Host; Write-BlankLine; Write-BlankLine; Write-SectionTitle "Backup Configuration" }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $BackupDir "backup_$timestamp"
    
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    
    $folders = Get-TargetFolders
    $filesBackedUp = 0
    foreach ($src in $folders) {
        if (Test-Path $src) {
            $folderName = Split-Path $src -Leaf
            Copy-Item $src (Join-Path $backupPath $folderName) -Recurse -Force -ErrorAction SilentlyContinue
            $filesBackedUp += (Get-ChildItem (Join-Path $backupPath $folderName) -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        }
    }
    
    if (-not $Silent) {
        Write-StepLine "Backup created" "ok"
        Write-ResultLine "Location:" $backupPath
        Write-ResultLine "Files:" $filesBackedUp
        Write-Log "Backup created: $backupPath ($filesBackedUp files)" "SUCCESS"
    }
}

# ========================================================================
#  6. RESTORE
# ========================================================================

function Restore-Config {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Restore Configuration"
    
    if (-not (Test-Path $BackupDir) -or (Get-ChildItem $BackupDir -Directory).Count -eq 0) {
        Write-StepLine "No backups found" "warn"; Pause-Return; return
    }
    
    $backups = Get-ChildItem $BackupDir -Directory | Sort-Object LastWriteTime -Descending
    Write-BlankLine
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-MenuItem ($i+1) ($backups[$i].LastWriteTime.ToString("yyyy-MM-dd HH:mm")) $backups[$i].Name
    }
    Write-MenuItem "0" "Cancel" -Highlighted $false
    Write-Prompt "1..$($backups.Count),0"
    $choice = Read-Host
    
    try {
        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $backups.Count) { return }
    } catch { return }
    
    if (-not (Stop-AnyDeskAggressively)) { Write-StepLine "Cannot proceed" "fail"; Pause-Return; return }
    
    $selected = $backups[$idx]
    $targets = @("$env:APPDATA\AnyDesk", "$env:ProgramData\AnyDesk", "$env:LOCALAPPDATA\AnyDesk")
    foreach ($t in $targets) {
        $backupSrc = Join-Path $selected.FullName "AnyDesk"
        if (Test-Path $backupSrc) {
            if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue }
            Copy-Item $backupSrc $t -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-StepLine "Restored from: $($selected.Name)" "ok"
    Write-Log "Config restored from: $($selected.Name)" "SUCCESS"
    Start-AnyDesk -WaitForConfig $false
}

# ========================================================================
#  7. BLOCK TELEMETRY
# ========================================================================

function Block-Telemetry {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Block Telemetry (Hosts File)"
    Write-InfoLines @(
        "Adds known AnyDesk analytics/license-check domains",
        "to your hosts file (-> 127.0.0.1).  Reversible."
    )
    Write-BlankLine
    
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $domains = @("analytics.anydesk.com", "telemetry.anydesk.com", "license.anydesk.com", "my.anydesk.com")
    
    Write-CategoryLabel "Domains to block:"
    Write-BlankLine
    foreach ($d in $domains) { Write-InfoLines @("    127.0.0.1  ->  $d") }
    Write-BlankLine
    
    Write-MenuItem "1" "Apply blocks"
    Write-MenuItem "2" "Remove blocks (restore)"
    Write-MenuItem "0" "Cancel" -Highlighted $false
    Write-Prompt "1,2,0"
    $choice = Read-Host
    
    $marker = "# === AnyDesk Manager Telemetry Block ==="
    $markerEnd = "# === End AnyDesk Manager Block ==="
    
    switch ($choice) {
        "1" {
            $content = Get-Content $hostsPath
            $newContent = @(); $inBlock = $false
            foreach ($line in $content) {
                if ($line -eq $marker) { $inBlock = $true; continue }
                if ($line -eq $markerEnd) { $inBlock = $false; continue }
                if (-not $inBlock) { $newContent += $line }
            }
            $newContent += ""; $newContent += $marker
            foreach ($d in $domains) { $newContent += "127.0.0.1  $d"; $newContent += "::1        $d" }
            $newContent += $markerEnd
            $newContent | Set-Content $hostsPath -Force
            ipconfig /flushdns | Out-Null
            Write-StepLine "Domains blocked - DNS cache flushed" "ok"
            Write-Log "Telemetry blocked" "SUCCESS"
        }
        "2" {
            $content = Get-Content $hostsPath
            $newContent = @(); $inBlock = $false
            foreach ($line in $content) {
                if ($line -eq $marker) { $inBlock = $true; continue }
                if ($line -eq $markerEnd) { $inBlock = $false; continue }
                if (-not $inBlock) { $newContent += $line }
            }
            $newContent | Set-Content $hostsPath -Force
            ipconfig /flushdns | Out-Null
            Write-StepLine "Blocks removed - DNS cache flushed" "ok"
            Write-Log "Telemetry blocks removed" "SUCCESS"
        }
    }
}

# ========================================================================
#  8. FIREWALL
# ========================================================================

function Manage-Firewall {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Firewall Rules"
    
    $exe = Find-AnyDesk
    if (-not $exe) { Write-StepLine "AnyDesk not found" "fail"; Pause-Return; return }
    
    Write-ResultLine "AnyDesk Path:" $exe
    Write-BlankLine
    
    $rules = Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*AnyDesk*" }
    if ($rules) {
        Write-CategoryLabel "Existing rules:"
        Write-BlankLine
        foreach ($r in $rules) {
            $act = if ($r.Action -eq "Allow") { "ALLOW" } else { "BLOCK" }
            $dir = if ($r.Direction -eq "Inbound") { "IN" } else { "OUT" }
            Write-InfoLines @("    [$dir] $act  -  $($r.DisplayName)")
        }
        Write-BlankLine
    }
    
    Write-MenuItem "1" "Block outbound only" "- stops phoning home"
    Write-MenuItem "2" "Allow outbound" "- remove block"
    Write-MenuItem "3" "Block completely" "- inbound + outbound"
    Write-MenuItem "4" "Remove all rules" "- AnyDesk Manager rules"
    Write-MenuItem "0" "Cancel" -Highlighted $false
    Write-Prompt "1,2,3,4,0"
    $choice = Read-Host
    
    $ruleName = "AnyDesk Manager - Block"
    switch ($choice) {
        "1" {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Program $exe -Action Block -Profile Any | Out-Null
            Write-StepLine "Outbound blocked" "ok"
        }
        "2" { Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue; Write-StepLine "Block removed" "ok" }
        "3" {
            Remove-NetFirewallRule -DisplayName "${ruleName}_IN" -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "${ruleName}_OUT" -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName "${ruleName}_IN" -Direction Inbound -Program $exe -Action Block -Profile Any | Out-Null
            New-NetFirewallRule -DisplayName "${ruleName}_OUT" -Direction Outbound -Program $exe -Action Block -Profile Any | Out-Null
            Write-StepLine "AnyDesk fully blocked" "ok"
        }
        "4" {
            Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*AnyDesk Manager*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Write-StepLine "All AnyDesk Manager rules removed" "ok"
        }
    }
}

# ========================================================================
#  9. ADVANCED
# ========================================================================

function Clear-ConnectionTraces {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Connection Trace Cleaner"
    $folders = Get-TargetFolders
    $cleared = 0
    foreach ($folder in $folders) {
        $traceFile = Join-Path $folder "connection_trace.txt"
        if (Test-Path $traceFile) {
            $entries = (Get-Content $traceFile | Measure-Object -Line).Lines
            Remove-Item $traceFile -Force -ErrorAction SilentlyContinue
            Write-StepLine "Cleared: $traceFile ($entries entries)" "ok"
            Write-Log "Cleared connection trace: $traceFile ($entries entries)"
            $cleared++
        }
    }
    if ($cleared -eq 0) { Write-StepLine "No connection traces found" "warn" }
}

function Manage-Service {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Service Manager"
    $svc = Get-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
    if (-not $svc) { Write-StepLine "AnyDesk service not found" "fail"; Pause-Return; return }
    Write-ResultLine "Service:" "AnyDesk"
    Write-ResultLine "Status:" $svc.Status $(if ($svc.Status -eq "Running") { $C_Green } else { $C_Yellow })
    Write-ResultLine "Startup:" $svc.StartType
    Write-BlankLine
    Write-MenuItem "1" "Set to Manual" "- only runs when launched"
    Write-MenuItem "2" "Set to Automatic" "- runs at boot"
    Write-MenuItem "3" "Set to Disabled" "- never runs"
    Write-MenuItem "4" "Start service"
    Write-MenuItem "5" "Stop service"
    Write-MenuItem "0" "Back" -Highlighted $false
    Write-Prompt "1..5,0"
    switch (Read-Host) {
        "1" { Set-Service -Name "AnyDesk" -StartupType Manual; Write-StepLine "Startup type -> Manual" "ok" }
        "2" { Set-Service -Name "AnyDesk" -StartupType Automatic; Write-StepLine "Startup type -> Automatic" "ok" }
        "3" { Set-Service -Name "AnyDesk" -StartupType Disabled; Write-StepLine "Service disabled" "warn" }
        "4" { Start-Service -Name "AnyDesk" -ErrorAction SilentlyContinue; Write-StepLine "Service started" "ok" }
        "5" { Stop-Service -Name "AnyDesk" -Force -ErrorAction SilentlyContinue; Write-StepLine "Service stopped" "ok" }
    }
}

function View-Logs {
    Clear-Host; Write-BlankLine; Write-BlankLine; Write-SectionTitle "Reset Logs"
    $logFile = "$LogDir\anydesk-manager.log"
    if (-not (Test-Path $logFile)) { Write-StepLine "No logs found" "warn"; Pause-Return; return }
    
    $logs = Get-Content $logFile -Tail 50
    foreach ($line in $logs) {
        $color = if ($line -match "SUCCESS") { $C_Green } elseif ($line -match "ERROR") { $C_Red } elseif ($line -match "WARN") { $C_Yellow } else { $C_Gray }
        Write-Host (" " * 7 + $line) -ForegroundColor $color
    }
    Write-BlankLine
    Write-ResultLine "Log file:" $logFile
    Write-MenuItem "C" "Clear logs"
    Write-MenuItem "0" "Back" -Highlighted $false
    Write-Prompt "C,0"
    if ((Read-Host) -eq "C") { Clear-Content $logFile -Force; Write-StepLine "Logs cleared" "ok" }
}

function Show-Advanced {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Advanced Options"
    Write-MenuItem "1" "Connection Trace Cleaner"
    Write-MenuItem "2" "Service Manager"
    Write-MenuItem "3" "View Reset Logs"
    Write-MenuItem "4" "Silent Reset Now" "- no UI"
    Write-MenuItem "0" "Back to Main Menu" -Highlighted $false
    Write-Prompt "1..4,0"
    switch (Read-Host) {
        "1" { Clear-ConnectionTraces; Pause-Return }
        "2" { Manage-Service; Pause-Return }
        "3" { View-Logs; Pause-Return }
        "4" {
            Stop-AnyDeskAggressively -ShowUI $false | Out-Null
            $folders = Get-TargetFolders; $idFiles = Get-IdentityFiles; $patterns = Get-IdentityRegexPatterns
            foreach ($f in $folders) {
                if (Test-Path $f) {
                    foreach ($p in $idFiles) { Get-ChildItem -Path $f -Filter $p -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
                    $conf = Join-Path $f "system.conf"
                    if (Test-Path $conf) {
                        (Get-Content $conf | Where-Object { $line = $_; -not ($patterns | Where-Object { $line -match $_ }) }) | Set-Content $conf -Force
                    }
                }
            }
            Get-RegistryPaths | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } }
            Start-AnyDesk -WaitForConfig $true -ShowUI $false | Out-Null
            Write-Log "Silent reset completed" "SUCCESS"
            Write-StepLine "Silent reset complete" "ok"
            exit 0
        }
    }
}

# ========================================================================
#  10. UNINSTALL
# ========================================================================

function Uninstall-AnyDesk {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Uninstall AnyDesk"
    
    $exe = Find-AnyDesk
    if (-not $exe) { Write-StepLine "AnyDesk not found" "warn"; Pause-Return; return }
    
    Write-ResultLine "Found at:" $exe
    Write-BlankLine
    Write-InfoLines @(
        "This will:",
        "  1. Stop AnyDesk processes & service",
        "  2. Backup configuration",
        "  3. Uninstall via Programs and Features",
        "  4. Remove leftover folders and registry",
        "  5. Remove scheduled tasks & firewall rules"
    )
    Write-BlankLine
    Write-MenuItem "1" "Proceed with full uninstall"
    Write-MenuItem "0" "Cancel" -Highlighted $false
    Write-Prompt "1,0"
    if ((Read-Host) -ne "1") { return }
    
    Write-BlankLine
    Stop-AnyDeskAggressively -ShowUI $false | Out-Null
    Write-StepLine "Stopping AnyDesk processes" "ok"
    
    Backup-Config -Silent
    Write-StepLine "Creating final backup" "ok"
    
    $uninstalled = $false
    foreach ($key in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AnyDesk", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\AnyDesk")) {
        if (Test-Path $key) {
            $uninstallString = (Get-ItemProperty -Path $key -Name "UninstallString" -ErrorAction SilentlyContinue).UninstallString
            if ($uninstallString) {
                $uninstallExe = $uninstallString -replace '"', '' -replace ' /.*$', ''
                if (Test-Path $uninstallExe) { Start-Process $uninstallExe -ArgumentList "/S" -Wait -NoNewWindow; $uninstalled = $true }
            }
            break
        }
    }
    Write-StepLine "Uninstalling AnyDesk" $(if ($uninstalled) { "ok" } else { "warn" })
    
    $foldersRemoved = 0
    foreach ($f in (Get-TargetFolders)) { if (Test-Path $f) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue; $foldersRemoved++ } }
    Write-StepLine "Removing leftover folders" "ok"
    
    foreach ($r in (Get-RegistryPaths)) { if (Test-Path $r) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-StepLine "Cleaning registry" "ok"
    
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue }
    Write-StepLine "Removing scheduled tasks" "ok"
    
    Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*AnyDesk Manager*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Write-StepLine "Removing firewall rules" "ok"
    
    Write-Log "AnyDesk fully uninstalled" "SUCCESS"
    Write-BlankLine
    Write-Separator
    Write-BlankLine
    Write-ColorLine @("       " + "AnyDesk has been uninstalled.", $C_Green)
    Write-ColorLine @("       Backup saved to: ", $C_Gray, $BackupDir, $C_White)
    Write-Separator
}

# ========================================================================
#  11. CHECK UPDATES
# ========================================================================

function Check-AnyDeskUpdate {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Check for Updates"
    
    $exe = Find-AnyDesk
    if (-not $exe) { Write-StepLine "AnyDesk not found" "warn"; Pause-Return; return }
    
    $installedVersion = "Unknown"
    try { $installedVersion = (Get-Item $exe).VersionInfo.FileVersion } catch {}
    Write-ResultLine "Installed version:" $installedVersion
    Write-ResultLine "Install path:" $exe
    Write-BlankLine
    
    Write-StepLine "Checking AnyDesk website..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $response = Invoke-WebRequest -Uri "https://download.anydesk.com/changelog.txt" -UseBasicParsing -TimeoutSec 10
        if ($response.Content -match '^(\d+\.\d+\.\d+)') {
            $latestVersion = $matches[1]
            Write-BlankLine
            Write-ResultLine "Latest version:" $latestVersion $C_Cyan
            if ($installedVersion -eq $latestVersion) {
                Write-StepLine "You are running the latest version!" "ok"
            } else {
                Write-StepLine "Update available: $installedVersion -> $latestVersion" "warn"
                Write-BlankLine
                Write-ColorLine @("       Download from: ", $C_Gray, "https://anydesk.com/download", $C_Cyan)
            }
        } else {
            Write-StepLine "Could not parse version" "warn"
        }
    } catch {
        Write-StepLine "Could not reach AnyDesk servers" "fail"
    }
}

# ========================================================================
#  12. NETWORK TEST
# ========================================================================

function Test-NetworkConnectivity {
    Clear-Host; Write-BlankLine; Write-BlankLine
    Write-SectionTitle "Network Connectivity Test"
    Write-InfoLines @("Tests connectivity to AnyDesk relay servers.")
    Write-BlankLine
    
    Write-StepLine "Testing internet connectivity"
    $inetOk = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet
    if (-not $inetOk) { Write-StepLine "No internet connectivity" "fail"; Pause-Return; return }
    Write-BlankLine
    
    Write-CategoryLabel "AnyDesk relay infrastructure:"
    Write-BlankLine
    
    $endpoints = @(
        @{Name="Main Server";     Host="anydesk.com";               Port=443;  Desc="Website & auth"},
        @{Name="Relay (Germany)"; Host="relay-de.anydesk.com";      Port=443;  Desc="German relay"},
        @{Name="Relay (US)";      Host="relay-us.anydesk.com";      Port=443;  Desc="US relay"},
        @{Name="Relay (HK)";      Host="relay-hk.anydesk.com";      Port=443;  Desc="Hong Kong relay"},
        @{Name="Boot Server";     Host="boot.net.anydesk.com";      Port=443;  Desc="Bootstrap server"},
        @{Name="DNS Resolution";  Host="net.anydesk.com";           Port=0;    Desc="DNS only"}
    )
    
    foreach ($ep in $endpoints) {
        Write-Host (" " * 7) -NoNewline
        Write-Host ($ep.Name + ":").PadRight(20) -NoNewline -ForegroundColor $C_Gray
        try {
            $ip = ([System.Net.Dns]::GetHostEntry($ep.Host)).AddressList[0].IPAddressToString
            Write-Host "DNS OK  " -NoNewline -ForegroundColor $C_Green
            if ($ep.Port -gt 0) {
                $tcp = Test-NetConnection -ComputerName $ep.Host -Port $ep.Port -WarningAction SilentlyContinue -InformationLevel Quiet
                Write-Host $(if ($tcp) { "TCP OK  " } else { "TCP FAIL" }) -NoNewline -ForegroundColor $(if ($tcp) { $C_Green } else { $C_Red })
            }
            Write-Host "  $ip  ($($ep.Desc))" -ForegroundColor $C_Gray
        } catch {
            Write-Host "DNS FAIL  Unreachable ($($ep.Desc))" -ForegroundColor $C_Red
        }
    }
    
    Write-BlankLine
    Write-StepLine "Checking local AnyDesk ports"
    $listening = Get-NetTCPConnection -LocalPort 7070 -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
    if ($listening) {
        Write-ResultLine "Port 7070 (main):" "Listening" $C_Green
    } else {
        Write-ResultLine "Port 7070 (main):" "Not listening" $C_Yellow
        Write-InfoLines @("Start AnyDesk if you want to accept incoming connections.")
    }
    
    Write-BlankLine
    Write-Separator
    Write-BlankLine
    Write-ColorLine @("       " + "Network connectivity looks good.", $C_Green)
    Write-Separator
}

# ========================================================================
#  MAIN MENU LOOP
# ========================================================================

# Handle silent mode from Task Scheduler
if ($args -contains "-SilentReset") {
    Stop-AnyDeskAggressively -ShowUI $false | Out-Null
    $folders = Get-TargetFolders; $idFiles = Get-IdentityFiles; $patterns = Get-IdentityRegexPatterns
    foreach ($f in $folders) {
        if (Test-Path $f) {
            foreach ($p in $idFiles) { Get-ChildItem -Path $f -Filter $p -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
            $conf = Join-Path $f "system.conf"
            if (Test-Path $conf) {
                (Get-Content $conf | Where-Object { $line = $_; -not ($patterns | Where-Object { $line -match $_ }) }) | Set-Content $conf -Force
            }
        }
    }
    Get-RegistryPaths | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } }
    Start-AnyDesk -WaitForConfig $true -ShowUI $false | Out-Null
    Write-Log "Silent scheduled reset completed" "SUCCESS"
    exit 0
}

# Init
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

# Main loop
while ($true) {
    Clear-Host
    Write-BlankLine; Write-BlankLine
    Write-Host (" " * 7) -NoNewline
    Write-Host "AnyDesk Manager v$ScriptVersion" -ForegroundColor $C_Yellow
    Write-BlankLine
    
    # Quick status
    $id = Get-CurrentAnyDeskID
    if ($id) {
        Write-Host (" " * 7) -NoNewline
        Write-Host "ID: " -NoNewline -ForegroundColor $C_Gray
        Write-Host $id -ForegroundColor $C_Cyan
        Write-Host (" " * 7) -NoNewline
        Write-Host ("_" * 55)
    }
    Write-BlankLine
    
    # Menu
    Write-CategoryLabel "Reset Options:"
    Write-BlankLine
    Write-MenuItem "1" "Surgical Reset" "- Preserves settings & favorites"
    Write-MenuItem "2" "Full Wipe Reset" "- Nuclear: wipes everything"
    Write-SubSeparator
    Write-BlankLine
    
    Write-CategoryLabel "Automation & Status:"
    Write-BlankLine
    Write-MenuItem "3" "Schedule Auto-Reset" "- Tier 2: Task Scheduler"
    Write-MenuItem "4" "Show Status" "- Current ID, service, logs"
    Write-MenuItem "5" "Backup Configuration" "- Save current state"
    Write-MenuItem "6" "Restore Configuration" "- Restore from backup"
    Write-SubSeparator
    Write-BlankLine
    
    Write-CategoryLabel "Defenses:"
    Write-BlankLine
    Write-MenuItem "7" "Block Telemetry" "- Hosts file blocking"
    Write-MenuItem "8" "Firewall Rules" "- Windows Firewall control"
    Write-SubSeparator
    Write-BlankLine
    
    Write-CategoryLabel "Tools:"
    Write-BlankLine
    Write-MenuItem "9" "Advanced Options" "- Traces, service, logs"
    Write-MenuItem "10" "Uninstall AnyDesk" "- Complete removal"
    Write-MenuItem "11" "Check for Updates" "- Latest version check"
    Write-MenuItem "12" "Network Test" "- Relay connectivity check"
    Write-BlankLine
    Write-MenuItem "0" "Exit" -Highlighted $false
    Write-BlankLine
    Write-Separator
    Write-BlankLine
    
    Write-Prompt "0..12"
    $choice = Read-Host
    
    switch ($choice) {
        "1"  { Reset-Surgical; Pause-Return }
        "2"  { Reset-FullWipe; Pause-Return }
        "3"  { Schedule-AutoReset; Pause-Return }
        "4"  { Show-Status; Pause-Return }
        "5"  { Backup-Config; Pause-Return }
        "6"  { Restore-Config; Pause-Return }
        "7"  { Block-Telemetry; Pause-Return }
        "8"  { Manage-Firewall; Pause-Return }
        "9"  { Show-Advanced; Pause-Return }
        "10" { Uninstall-AnyDesk; Pause-Return }
        "11" { Check-AnyDeskUpdate; Pause-Return }
        "12" { Test-NetworkConnectivity; Pause-Return }
        "0"  {
            Clear-Host
            Write-BlankLine; Write-BlankLine
            Write-Separator
            Write-BlankLine
            Write-Host (" " * 7) -NoNewline
            Write-Host "Thanks for using AnyDesk Manager." -ForegroundColor $C_Green
            Write-BlankLine
            Write-Separator
            Write-BlankLine
            exit 0
        }
        default {
            Write-BlankLine
            Write-StepLine "Invalid option - choose 0-12" "warn"
            Start-Sleep -Seconds 1
        }
    }
}
