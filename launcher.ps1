<#
.NOTES
    AnyDesk Manager Launcher — tiny bootstrap that doesn't trigger AMSI.
    Run: irm https://raw.githubusercontent.com/Tastico/anydesk-manager/main/launcher.ps1 | iex
#>
param()

$url = "https://raw.githubusercontent.com/Tastico/anydesk-manager/main/anydesk-manager.ps1"
$tmp = "$env:TEMP\anydesk-manager.ps1"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Not admin — download, save, re-launch
    Write-Host "Downloading AnyDesk Manager..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $script = (New-Object Net.WebClient).DownloadString($url)
    [System.IO.File]::WriteAllText($tmp, $script, [System.Text.Encoding]::Unicode)
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$tmp`"" -Verb RunAs
    exit
}

# Already admin — download and run directly
Write-Host "Downloading AnyDesk Manager..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script = (New-Object Net.WebClient).DownloadString($url)
[System.IO.File]::WriteAllText($tmp, $script, [System.Text.Encoding]::Unicode)
& $tmp
