# CleanPC – Windows 11 Safe Cleanup Tool v5

A single batch file that frees disk space on Windows 10/11 without touching
anything you would miss. Cookies, logins, history, chats, game files and the
Downloads folder are never deleted.

## Features

- **Quick clean** – temp folders (age-filtered), crash dumps, error reports,
  DirectX / NVIDIA / AMD / Intel shader caches, thumbnail cache
- **Deep clean** – quick + Windows Update cache, Delivery Optimization,
  old Windows logs, Disk Cleanup with a vetted handler list, Recycle Bin on every drive
- **Browser caches** – every profile of Chrome, Edge, Brave, Vivaldi, Opera / GX,
  Yandex, Chromium and Firefox (cache folders only)
- **App caches** – Teams (new and classic), Discord, Slack, Steam, Epic, Adobe,
  Java, OneDrive logs, Office add-ins
- **Developer caches** (opt-in) – pip, uv, Poetry, npm, Yarn, pnpm, Bun, Deno,
  NuGet, Gradle, Cargo, Go, VS Code / Cursor, JetBrains, conda, Docker
- **MAXIMUM clean** – deep + browsers + apps in one run
- **Advanced space options** – hibernation file, System Restore cap,
  Windows.old, DISM ResetBase, CompactOS, reserved storage. Each one explains
  the trade-off and asks first
- **System repair** – DISM ScanHealth → RestoreHealth → SFC → component cleanup
- **Disk report** – where the space went, biggest files, WSL/Docker disks,
  and folders you should *not* delete by hand
- **Monthly scheduled task** – quick clean, or deep clean only when space is low

## Safety

- Dry-run mode shows what would be deleted without deleting anything
- Path guard refuses wildcards, `..`, shallow paths and system roots
- Junctions and symlinks are never followed
- Temp files newer than 1 day (configurable) are left alone
- Optional System Restore point before deep / maximum clean
- Every run is logged to `%LOCALAPPDATA%\CleanPC\` (text + CSV)

## Usage

Download `CleanPC_v5.bat` and double-click it. It asks for administrator
rights and opens an interactive menu.

Or from the command line:

```bat
CleanPC_v5.bat /quick
CleanPC_v5.bat /deep /dryrun
CleanPC_v5.bat /max /olderthan:3
CleanPC_v5.bat /report
CleanPC_v5.bat /help
```

| Option | Effect |
|---|---|
| `/dryrun` | report only, delete nothing |
| `/quiet` | no prompts – for Task Scheduler |
| `/ifbelow:GB` | only clean when free space is below GB |
| `/olderthan:N` | keep temp files newer than N days (default 1) |
| `/nosizes` | skip size measurement – much faster |
| `/allusers` | also clean temp of every user profile |
| `/restorepoint` | create a restore point even in quiet mode |
| `/desktoplog` | write the log to the Desktop |

Run `/help` for the full list.

**Exit codes:** 0 ok · 1 elevation failed · 2 a step failed · 3 bad usage

## Disclaimer

Use at your own risk. Try `/dryrun` first to see what would be removed.

## License

MIT
