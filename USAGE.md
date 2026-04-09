# Usage Guide

Complete usage guide for the System Maintenance Tool v6.0.0.

---

## Table of Contents

- [First-Time Setup](#first-time-setup)
- [Running the Tool](#running-the-tool)
- [Using the Executables](#using-the-executables)
- [Command-Line Parameters](#command-line-parameters)
- [Common Scenarios](#common-scenarios)
- [Understanding the Output](#understanding-the-output)
- [Sample Dry-Run Output](#sample-dry-run-output)
- [Troubleshooting](#troubleshooting)

---

## First-Time Setup

### Enabling PowerShell Script Execution

Windows blocks PowerShell scripts by default. Choose one method:

**Method 1: Per-session bypass (recommended — no permanent changes)**

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\SystemMaintenanceTool.ps1 -DryRun
```

**Method 2: Per-user setting (persists across sessions)**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Method 3: Inline bypass (single command)**

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\SystemMaintenanceTool.ps1 -DryRun
```

**Method 4: Use the .exe build (no policy changes needed)**

```cmd
.\build\SystemMaintenanceTool-x64.exe -DryRun
```

### Running as Administrator

19 of 42 modules require administrator privileges. To run elevated:

1. Right-click **PowerShell** or **Windows Terminal**
2. Select **Run as Administrator**
3. Navigate to the tool directory and run the script

Or from an existing terminal:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PWD\SystemMaintenanceTool.ps1`" -DryRun"
```

---

## Running the Tool

### Interactive Mode (Default)

```powershell
.\SystemMaintenanceTool.ps1
```

The tool presents a categorized menu. Select modules by number (comma-separated), press `A` for all, or `Q` to quit.

### Dry-Run Mode

```powershell
.\SystemMaintenanceTool.ps1 -DryRun
```

Shows exactly what would be cleaned and how much space would be recovered. **No files are modified or deleted.** Always start here.

### Specific Modules

```powershell
.\SystemMaintenanceTool.ps1 -Modules TempFiles,BrowserCache,ShaderCache
```

### Skip Modules

```powershell
.\SystemMaintenanceTool.ps1 -SkipModules DiskCleanup,EventLogs
```

### Non-Interactive (Automation)

```powershell
.\SystemMaintenanceTool.ps1 -NonInteractive -DryRun
```

Runs all modules without prompts. Suitable for scheduled tasks and CI/CD.

### Custom Log Path

```powershell
.\SystemMaintenanceTool.ps1 -LogPath "D:\Logs\Maintenance"
```

---

## Using the Executables

Pre-built `.exe` files are in the `build/` folder. These embed PowerShell inside and require no script execution policy changes.

| Binary | When to Use |
|--------|------------|
| `SystemMaintenanceTool-x64.exe` | 64-bit Intel/AMD (most modern PCs) |
| `SystemMaintenanceTool-x86.exe` | 32-bit Intel/AMD (older hardware) |
| `SystemMaintenanceTool-AnyCPU.exe` | ARM64 or any platform (universal) |

```cmd
:: Dry-run with the executable
.\build\SystemMaintenanceTool-x64.exe -DryRun

:: Run specific modules
.\build\SystemMaintenanceTool-x64.exe -Modules TempFiles,RecycleBin -NonInteractive
```

> **Windows SmartScreen:** On first run, Windows may show a warning. Right-click the `.exe` > **Properties** > check **Unblock** > OK.

---

## GUI Launcher

The tool includes a WinForms GUI with retro CRT styling:

```powershell
# Run the GUI script
.\SystemMaintenanceGUI.ps1

# Or use the prebuilt executable
.\build\SystemMaintenanceGUI-x64.exe
```

**GUI Features:**
- Tree view with checkboxes for module selection (organized by category)
- Dry-Run and Sound Effect toggles
- Live log output with color-coded messages
- Progress bar with percentage
- Module count and space recovered display

**GUI Executables:**

| Binary | Architecture |
|--------|-------------|
| `SystemMaintenanceGUI-x64.exe` | 64-bit Intel/AMD |
| `SystemMaintenanceGUI-x86.exe` | 32-bit Intel/AMD |
| `SystemMaintenanceGUI-AnyCPU.exe` | Universal (ARM64) |

---

## Retro TUI Mode

Full-screen DOS/Norton Commander style terminal UI:

```powershell
.\SystemMaintenanceTool.ps1 -RetroUI
.\SystemMaintenanceTool.ps1 -RetroUI -Sound    # with sound effects
```

**Keyboard Controls:**
| Key | Action |
|-----|--------|
| Up/Down Arrow | Navigate modules |
| Space | Toggle module selection |
| A | Select all modules |
| N | Deselect all modules |
| Enter | Run selected modules |
| Escape | Exit |

---

## Sound Effects

Enable retro beep sounds with the `-Sound` switch:

```powershell
.\SystemMaintenanceTool.ps1 -Sound
.\SystemMaintenanceTool.ps1 -DryRun -Sound
.\SystemMaintenanceTool.ps1 -RetroUI -Sound
```

**Sound Events:**
| Event | Sound |
|-------|-------|
| Welcome | Ascending C-E-G chord |
| Scan start/tick | Short blips |
| Scan complete | Rising tone |
| Action start | Alert beep |
| Success | Ascending chord |
| Error | Descending low tone |
| Warning | Attention beep |
| Complete | Victory fanfare jingle |

Uses `[Console]::Beep()` -- no audio files or drivers required. Silently handles missing audio hardware.

---

## Command-Line Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-DryRun` | Switch | Preview mode -- no changes made |
| `-NonInteractive` | Switch | Skip all prompts (for automation) |
| `-Modules` | String[] | Comma-separated list of modules to run |
| `-SkipModules` | String[] | Comma-separated list of modules to skip |
| `-LogPath` | String | Custom directory for log files |
| `-RetroUI` | Switch | Full-screen green-on-black retro TUI mode |
| `-Sound` | Switch | Enable retro beep sound effects |

### Available Module Names

**Basic:** `TempFiles`, `WindowsUpdate`, `RecycleBin`, `BrowserCache`, `EventLogs`

**Advanced:** `PrefetchCleanup`, `DeliveryOptimization`, `WindowsOldCleanup`, `CrashDumps`, `InstallerCleanup`, `ShaderCache`, `ThumbCacheCleanup`, `ErrorReporting`, `WindowsLogFiles`, `DefenderCache`, `SearchIndexCleanup`, `ShadowCopyCleanup`, `DevToolCaches`, `AppCacheCleanup`, `DotNetCleanup`, `OfficeCleanup`, `CloudStorageCleanup`, `AdobeCleanup`, `JavaCleanup`, `ChkdskFragments`, `IISLogCleanup`

**Privacy:** `WindowsPrivacyCleanup`, `BrowserPrivacyCleanup`

**Tools:** `DiskCleanup`, `ComponentStoreCleanup`, `DNSCacheFlush`, `WindowsStoreCache`, `FontCacheRebuild`, `FreeSpaceWiper`

**Analysis:** `StartupAnalysis`, `ServiceAnalysis`, `SystemHealthCheck`, `NetworkAnalysis`, `LargeFileFinder`, `DuplicateFileFinder`, `ScheduledTaskReview`, `RestorePointAnalysis`

---

## Common Scenarios

### Quick User Cleanup (No Admin Required)

```powershell
.\SystemMaintenanceTool.ps1 -Modules TempFiles,RecycleBin,BrowserCache,ShaderCache,ThumbCacheCleanup
```

Typical recovery: 5-15 GB

### Developer Workstation Cleanup

```powershell
.\SystemMaintenanceTool.ps1 -Modules DevToolCaches,AppCacheCleanup,TempFiles,BrowserCache
```

Typical recovery: 10-30 GB (npm/NuGet/pip caches grow large)

### Full System Cleanup (Admin Required)

```powershell
# Run as Administrator
.\SystemMaintenanceTool.ps1 -Modules TempFiles,WindowsUpdate,RecycleBin,BrowserCache,EventLogs,PrefetchCleanup,DeliveryOptimization,CrashDumps,ShaderCache,ThumbCacheCleanup,ErrorReporting,WindowsLogFiles,DevToolCaches,AppCacheCleanup
```

### System Health Check Only (Read-Only)

```powershell
.\SystemMaintenanceTool.ps1 -Modules SystemHealthCheck,StartupAnalysis,LargeFileFinder,ScheduledTaskReview -DryRun
```

### Monthly Automated Maintenance (Scheduled Task)

```powershell
.\SystemMaintenanceTool.ps1 -NonInteractive -LogPath "C:\Logs\Maintenance"
```

### Privacy Cleanup (Browser & Windows)

```powershell
.\SystemMaintenanceTool.ps1 -Modules WindowsPrivacyCleanup,BrowserPrivacyCleanup
```

Clears recent documents, jump lists, clipboard, Run MRU, app history, plus browser cookies/history/form data for all 7 supported browsers. **Warning:** This will log you out of all browser sessions.

---

## Understanding the Output

### Progress Bars

Two progress bars appear during execution:

**Scan phase** — shows which module is being analyzed:
```
  [###############---------------] 50% (5/10) Scanning Browser Cache Cl...
```

**Execution phase** — shows which module is running:
```
  [######################--------] 73% (8/11) Application Cache Cleanup
```

### Status Indicators

| Prefix | Meaning |
|--------|---------|
| `[INFO]` | Informational — scanning, counting files |
| `[ACTION]` | An action is about to be performed |
| `[SUCCESS]` | Action completed successfully |
| `[WARNING]` | Non-critical issue (e.g., needs admin) |
| `[ERROR]` | Action failed |
| `[SKIP]` | Module or path was skipped |
| `[DETAIL]` | Safety rationale, impact explanation |

### Scan Results Table

Before any cleanup, a table shows what was found:

```
==============================================================================
  SYSTEM SCAN RESULTS
==============================================================================
  MODULE                     RECLAIMABLE     FILES  TYPE          STATUS
  ------------------------------------------------------------------------------
  Temp Files                     8.55 GB    27,356  Cleanup       Recoverable
  Recycle Bin                  553.41 MB        53  Cleanup       Recoverable
  Browser Caches                 4.65 GB    62,923  Cleanup       Recoverable
  Shader Cache                  46.98 MB       501  Cleanup       Recoverable
  Dev Tool Caches                8.56 GB   102,887  Cleanup       Recoverable
  System Health               -- Info --        --  Analysis      Ready
  ------------------------------------------------------------------------------
  TOTAL RECOVERABLE             22.35 GB   193,710
==============================================================================
```

### Summary Report

After all modules complete:

```
======================================================================
  MAINTENANCE SUMMARY REPORT
======================================================================
  Duration        : 00:59
  Mode            : DRY-RUN (no changes made)
  Disk Freed      : 24.24 GB
  Files Processed : 203,315
  Errors          : 0
  Actions Logged  : 19
======================================================================
```

---

## Sample Dry-Run Output

Below is real output from running 11 modules in dry-run mode on a developer workstation.

```
    +==============================================================+
    |       System Maintenance Tool  v5.0.0                        |
    |       Auditable - Safe - Transparent                         |
    +==============================================================+
    *** DRY-RUN MODE -- No changes will be made ***

    Date     : 2026-04-09 08:22:41
    Computer : DESKTOP-FJFLME4
    User     : Chaitanya
    Admin    : False
    Log File : logs\MaintenanceTool_20260409_082241.log

[INFO]     Modules selected: TempFiles, RecycleBin, BrowserCache, ShaderCache,
           ThumbCacheCleanup, DevToolCaches, AppCacheCleanup, StartupAnalysis,
           SystemHealthCheck, LargeFileFinder, ScheduledTaskReview

[INFO]     Scanning system for reclaimable space...
  [###---------------------------]  9% (1/11) Scanning Temporary File C...
  [#####-------------------------] 18% (2/11) Scanning Recycle Bin Cleanup
  [########----------------------] 27% (3/11) Scanning Browser Cache Cl...
  [###########-------------------] 36% (4/11) Scanning GPU Shader Cache...
  [##############----------------] 45% (5/11) Scanning Thumbnail Cache ...
  [################--------------] 55% (6/11) Scanning Developer Tool C...
  [###################-----------] 64% (7/11) Scanning Application Cach...
  [######################--------] 73% (8/11) Scanning Startup Program ...
  [#########################-----] 82% (9/11) Scanning System Health Re...
  [###########################---] 91% (10/11) Scanning Large File Finde...
  [##############################] 100% (11/11) Scanning Scheduled Task R...

==============================================================================
  SYSTEM SCAN RESULTS
==============================================================================
  MODULE                     RECLAIMABLE     FILES  TYPE          STATUS
  ------------------------------------------------------------------------------
  Temp Files                     8.55 GB    27,356  Cleanup       Recoverable
  Recycle Bin                  553.41 MB        53  Cleanup       Recoverable
  Browser Caches                 4.65 GB    62,923  Cleanup       Recoverable
  Shader Cache                  46.98 MB       501  Cleanup       Recoverable
  Thumbnail Cache               55.11 MB        30  Cleanup       Recoverable
  Dev Tool Caches                8.56 GB   102,887  Cleanup       Recoverable
  App Caches                     1.83 GB     9,565  Cleanup       Recoverable
  Startup Programs             11 items        11  Analysis      Ready
  System Health               -- Info --        --  Analysis      Ready
  Large File Finder           -- Info --        --  Analysis      Ready
  Task Review                  12 tasks        12  Analysis      Ready
  ------------------------------------------------------------------------------
  TOTAL RECOVERABLE             24.24 GB   203,315
==============================================================================

  DRY-RUN: Showing detailed breakdown per module below.

----------------------------------------------------------------------
  Temporary File Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Temp files are transient by design. Locked files are skipped.
[DETAIL]   IMPACT: Recovers disk space from accumulated temporary data.
[INFO]     Scanning: C:\Users\Chaitanya\AppData\Local\Temp
[INFO]     Found 13,678 files (4.28 GB)
[DETAIL]   Reason: User temp directory -- application scratch files
[ACTION]   [DRY-RUN] Would delete 13,678 files (4.28 GB)
[INFO]     Scanning: C:\WINDOWS\Temp
[SKIP]     No eligible files found in: C:\WINDOWS\Temp
[SUCCESS]  Temp cleanup complete. Total recoverable: 8.55 GB

----------------------------------------------------------------------
  Recycle Bin Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Recycle Bin contains files the user has already deleted.
[DETAIL]   IMPACT: Frees disk space from pending permanent deletions.
[INFO]     Recycle Bin contains 53 item(s).
[ACTION]   [DRY-RUN] Would empty Recycle Bin (53 items).

----------------------------------------------------------------------
  Browser Cache Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Only cached web assets are removed (images, scripts, CSS).
[DETAIL]   NOT TOUCHED: History, bookmarks, passwords, cookies, extensions.
[INFO]     Scanning Google Chrome...
[INFO]     Found 1,725 files (360.56 MB) in Chrome\Cache
[ACTION]   [DRY-RUN] Would delete 1,725 files (360.56 MB)
[INFO]     Found 7,515 files (747.18 MB) in Chrome\Code Cache
[ACTION]   [DRY-RUN] Would delete 7,515 files (747.18 MB)
[INFO]     Found 52,722 files (3.51 GB) in Chrome\Service Worker\CacheStorage
[ACTION]   [DRY-RUN] Would delete 52,722 files (3.51 GB)
[INFO]     Scanning Microsoft Edge...
[INFO]     Found 15 files (7.00 MB) in Edge\Cache
[ACTION]   [DRY-RUN] Would delete 15 files (7.00 MB)
[SUCCESS]  Browser cache cleanup complete.

----------------------------------------------------------------------
  GPU Shader Cache Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Shader caches are auto-rebuilt by the GPU driver on next use.
[DETAIL]   IMPACT: Brief stuttering in games/apps on first run as shaders recompile.
[INFO]     Found 359 files (40.75 MB) in NVIDIA\DXCache
[ACTION]   [DRY-RUN] Would delete 359 files (40.75 MB)
[INFO]     Found 16 files (321.89 KB) in NVIDIA\GLCache
[ACTION]   [DRY-RUN] Would delete 16 files (321.89 KB)
[INFO]     Found 126 files (5.91 MB) in D3DSCache
[ACTION]   [DRY-RUN] Would delete 126 files (5.91 MB)
[SUCCESS]  Shader cache cleanup complete.

----------------------------------------------------------------------
  Developer Tool Cache Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Package manager caches are re-downloaded on demand.
[DETAIL]   IMPACT: Next install/restore may take longer as packages are re-fetched.
[INFO]     Found npm cache: 99,017 files (6.96 GB)
[INFO]     Found pip cache: 3,248 files (1.29 GB)
[INFO]     Found NuGet cache: 53 files (200.97 MB)
[INFO]     Found cargo cache: 555 files (121.33 MB)
[INFO]     Total developer caches: 8.56 GB across 5 tools
[ACTION]   [DRY-RUN] Would delete 102,887 cached files (8.56 GB)

----------------------------------------------------------------------
  Application Cache Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Only cached/temp data removed. Settings and chat history preserved.
[DETAIL]   IMPACT: Apps may take slightly longer to start until caches rebuild.
[INFO]     Microsoft Teams (New): 7,588 files (1.11 GB)
[INFO]     Slack: 996 files (139.14 MB)
[INFO]     VS Code: 1,012 files (1.33 GB)
[ACTION]   [DRY-RUN] Would delete 9,596 cached files (2.57 GB) from 3 apps

----------------------------------------------------------------------
  Startup Program Analysis  [Risk: None (read-only)]
----------------------------------------------------------------------
[INFO]     This module is READ-ONLY. No changes will be made.
[INFO]     Found 20 startup item(s):

    [!] OneDrive (Registry)
        "C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background
        >> RECOMMENDATION: Review if this needs to run at startup.
    [ ] IDMan (Registry)
        C:\Program Files (x86)\Internet Download Manager\IDMan.exe /onboot
    [ ] Krisp (Registry)
        "C:\Users\Chaitanya\AppData\Local\Programs\Krisp\app-3.7.8\krisp.exe"
    [!] Adobe Acrobat Update Task (ScheduledTask)
        >> RECOMMENDATION: Review if this needs to run at startup.

[SUCCESS]  20 startup items analyzed. 4 flagged for review.
[DETAIL]   TIP: Use Task Manager > Startup tab to disable unnecessary items.

----------------------------------------------------------------------
  System Health Report  [Risk: None (read-only)]
----------------------------------------------------------------------
[INFO]     This module is READ-ONLY. No changes will be made.

    DISK HEALTH
    ------------------------------------------------------------
    C: [####################----------] 65.8% used  (325.62 GB free of 951.40 GB)

    MEMORY
    ------------------------------------------------------------
    Total: 63.7 GB | Used: 28.9 GB (45.4%) | Free: 34.8 GB

    SYSTEM UPTIME
    ------------------------------------------------------------
    Last boot: 2026-04-08 10:51:57
    Uptime:    0 days, 21 hours, 31 minutes

    WINDOWS VERSION
    ------------------------------------------------------------
    Edition: Windows 10 Pro
    Version: 25H2 (Build 10.0.26200.8037)

    RECENT SYSTEM ERRORS (Last 7 Days)
    ------------------------------------------------------------
    [04-08 10:57] Microsoft-Windows-TPM-WMI: Updated Secure Boot certificates...
    [04-08 10:52] BTHUSB: Mutual authentication between Bluetooth adapter...
    [04-08 10:52] Service Control Manager: CxUIUSvc service failed to start...

    TOP MEMORY CONSUMERS
    ------------------------------------------------------------
    elasticsearch-service-x64        1289 MB
    sqlservr                          743 MB
    TfsJobAgent                       735 MB
    chrome                            672 MB
    Code                              636 MB

----------------------------------------------------------------------
  Large File Finder (>500 MB)  [Risk: None (read-only)]
----------------------------------------------------------------------
[INFO]     This module is READ-ONLY. No files will be modified or deleted.
[INFO]     Scanning user directories for files larger than 500 MB...

    LARGE FILES ON C:
    ----------------------------------------------------------------------
        25.50 GB  1d ago  C:\hiberfil.sys
        15.95 GB  492d    ...Collection(17 courses)-20241202T151456Z-001.zip
        15.33 GB  250d    ...Documents\Camtasia\Rec 01-08-2025.trec
         5.91 GB  237d    ...Downloads\ubuntu-24.04.3-desktop-amd64.iso
         5.70 GB  354d    ...Downloads\Win10_22H2_English_x64.iso
         4.56 GB  543d    ...Documents\Windows-10.iso
         4.35 GB  543d    ...Downloads\kali-linux-2024.3-live-amd64.iso
         4.14 GB  544d    ...Documents\ProPlusRetail.img
         4.00 GB  1d ago  C:\pagefile.sys
         3.65 GB  236d    ...Virtual Machines\ubuntu\ubuntu-s001.vmdk
    ----------------------------------------------------------------------
    Total: 144.26 GB across 25 files

[DETAIL]   TIP: Review these files manually. Common culprits: VM images, ISOs, old backups.

----------------------------------------------------------------------
  Scheduled Task Review  [Risk: None (read-only)]
----------------------------------------------------------------------
[INFO]     This module is READ-ONLY. No tasks will be modified.
[INFO]     Scanning for third-party scheduled tasks...

    FLAGGED TASKS (likely unnecessary):
    [!] Adobe Acrobat Update Task  (Ready)
    [!] CCleaner 7 - Skip UAC  (Ready)

    THIRD-PARTY TASKS (review recommended):
    [?] Background monitor  (Running)
    [?] SoftLandingCreativeManagementTask  (Ready)

    Total active: 170 | Flagged: 2 | Third-party: 4

[DETAIL]   TIP: Disable flagged tasks via: Disable-ScheduledTask -TaskName '<name>'

======================================================================
  MAINTENANCE SUMMARY REPORT
======================================================================

  Duration        : 00:59
  Mode            : DRY-RUN (no changes made)
  Disk Freed      : 24.24 GB (would recover)
  Files Processed : 203,315
  Errors          : 0
  Actions Logged  : 19

  Actions Taken:
  ------------------------------------------------------------------
  [--] TempFiles          WouldDelete    User & System Temp
  [--] RecycleBin         WouldEmpty     Recycle Bin (53 items)
  [--] BrowserCache       WouldDelete    Chrome + Edge caches
  [--] ShaderCache        WouldDelete    NVIDIA + DirectX caches
  [--] ThumbCacheCleanup  WouldDelete    Thumbnail databases
  [--] DevToolCaches      WouldDelete    npm/pip/NuGet/cargo (8.56 GB)
  [--] AppCacheCleanup    WouldDelete    Teams/Slack/VS Code (2.57 GB)
  [OK] StartupAnalysis    Analyze        20 items, 4 flagged
  [OK] SystemHealthCheck  Analyze        System Health
  [OK] LargeFileFinder    Analyze        144.26 GB in 25 files
  [OK] ScheduledTaskReview Analyze       170 tasks, 2 flagged

  Recommendations:
  ------------------------------------------------------------------
  * Re-run as Administrator for full functionality.
  * Schedule this tool monthly for ongoing maintenance.
  * Review startup items flagged by the Startup Analysis module.
  * Consider running Windows Disk Cleanup for deeper system cleanup.

  Full log: logs\MaintenanceTool_20260409_082241.log
======================================================================
```

---

## Troubleshooting

### "Running scripts is disabled on this system"

```powershell
# Fix: Allow scripts for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Or use the .exe build instead
.\build\SystemMaintenanceTool-x64.exe -DryRun
```

### "Access denied" or modules showing "Needs Admin"

Run PowerShell as Administrator:
1. Press `Win+X` > **Windows Terminal (Admin)** or **PowerShell (Admin)**
2. Navigate to the tool folder and run again

### "Windows protected your PC" (SmartScreen)

For `.exe` files:
1. Right-click the `.exe` file
2. Click **Properties**
3. Check **Unblock** at the bottom
4. Click **OK**

### Script runs but finds 0 bytes

Most cleanup targets require admin. Run as Administrator to unlock all 32 modules.

### Tool is slow on Large File Finder

The tool scans user directories with depth limits for performance. Full drive scans are intentionally avoided. Typical scan time: 2-5 seconds.

### How to verify what was done

Check the log files in the `logs/` folder:
- `.log` file — full human-readable record of every action
- `.csv` file — import into Excel for analysis

```powershell
# View the latest log
Get-ChildItem .\logs\*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content

# View action summary
Get-ChildItem .\logs\*.csv | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Import-Csv | Format-Table
```
