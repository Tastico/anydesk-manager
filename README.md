# AnyDesk Manager

Reset AnyDesk commercial-use detection flags. A 12-tool PowerShell utility.

## Quick Start

```powershell
irm https://raw.githubusercontent.com/Tastico/anydesk-manager/main/anydesk-manager.ps1 | iex
```

Or double-click `anydesk-manager.cmd` — auto-elevates to admin.

## Tools

| # | Tool | What It Does |
|---|------|-------------|
| 1 | Surgical Reset | Removes identity files only — preserves settings |
| 2 | Full Wipe Reset | Nuclear: wipes everything, clean ID |
| 3 | Schedule Auto-Reset | Task Scheduler, runs as SYSTEM |
| 4 | Show Status | Current ID, service, traces |
| 5 | Backup / Restore | Config backup with timestamps |
| 7 | Block Telemetry | Hosts file blocking |
| 8 | Firewall Rules | Windows Firewall control |
| 10 | Uninstall AnyDesk | Complete removal |
| 11 | Check for Updates | Installed vs latest version |
| 12 | Network Test | DNS/TCP relay connectivity |

## How Surgical Reset Works

1. Captures current `ad.anynet.id`
2. Stops AnyDesk (5 aggressive cycles)
3. Deletes identity files: `service.auth`, `ad.session.token`, `*.trace`, `*.old`, `service.conf`, `connection_trace.txt`
4. Strips 5 identity keys from `system.conf` (preserves favorites/aliases)
5. Wipes registry: `HKLM`, `HKCU` AnyDesk keys
6. Starts AnyDesk, verifies new ID

## Requirements

- Windows 10/11, PowerShell 5.1+
- Administrator (auto-elevates)

## License

MIT
