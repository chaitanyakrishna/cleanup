# Example Output

Below is representative output from running the tool in dry-run mode with all 32 modules (v4.0.0).

---

```
    +==============================================================+
    |       System Maintenance Tool  v5.0.0                        |
    |       Auditable - Safe - Transparent                         |
    +==============================================================+
    *** DRY-RUN MODE -- No changes will be made ***

    Date     : 2026-04-08 23:56:23
    Computer : DESKTOP-FJFLME4
    User     : Chaitanya
    Admin    : False
    Log File : C:\Users\Chaitanya\Documents\cleanup\logs\MaintenanceTool_20260408_235623.log

[INFO]     Scanning system for waste data...
==============================================================================
  SYSTEM SCAN RESULTS
==============================================================================
  MODULE                      WASTE SIZE     FILES  TYPE          STATUS
  ------------------------------------------------------------------------------
  Temp Files                     8.55 GB    27,340  Cleanup       Recoverable
  Windows Update Cache           -- N/A --       0  Cleanup       Needs Admin
  Recycle Bin                  332.41 MB       128  Cleanup       Recoverable
  Browser Caches                 1.12 GB     4,220  Cleanup       Recoverable
  Event Logs                     -- N/A --       0  Cleanup       Needs Admin
  Prefetch Cache                 -- N/A --       0  Cleanup       Needs Admin
  Delivery Optimization          -- N/A --       0  Cleanup       Needs Admin
  Windows.old                    -- N/A --       0  Cleanup       Needs Admin
  Crash Dumps                    -- N/A --       0  Cleanup       Needs Admin
  Installer Patch Cache          -- N/A --       0  Cleanup       Needs Admin
  Shader Cache                  46.98 MB       501  Cleanup       Recoverable
  Thumbnail Cache               55.11 MB        30  Cleanup       Recoverable
  Error Reports                  -- N/A --       0  Cleanup       Needs Admin
  Diagnostic Logs                -- N/A --       0  Cleanup       Needs Admin
  Defender Cache                 -- N/A --       0  Cleanup       Needs Admin
  Search Index                   -- N/A --      --  System        Needs Admin
  Shadow Copies                  -- N/A --      --  System        Needs Admin
  Dev Tool Caches                8.56 GB     9,412  Cleanup       Recoverable
  App Caches                     1.82 GB     3,105  Cleanup       Recoverable
  .NET NGen Cache                -- N/A --       0  Cleanup       Needs Admin
  Disk Cleanup                   -- N/A --      --  System        Needs Admin
  Component Store                -- N/A --      --  System        Needs Admin
  DNS Cache                      -- N/A --      --  System        Needs Admin
  Store Cache                    -- N/A --      --  System        Ready
  Font Cache                     -- N/A --      --  System        Needs Admin
  Startup Analysis             -- Info --        --  Analysis      Ready
  Service Analysis             -- Info --        --  Analysis      Ready
  System Health                -- Info --        --  Analysis      Ready
  Network Analysis             -- Info --        --  Analysis      Ready
  Large File Finder            -- Info --        --  Analysis      Ready
  Duplicate Finder             -- Info --        --  Analysis      Ready
  Scheduled Tasks              -- Info --        --  Analysis      Ready
  ------------------------------------------------------------------------------
  TOTAL RECOVERABLE             20.51 GB    44,736
==============================================================================

  Proceed with cleanup? (Y/N): Y

[INFO]     Running all 32 modules...
```

## Module Output Examples

### Temporary File Cleanup

```
----------------------------------------------------------------------
  Temporary File Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Temp files are transient by design. Locked files are skipped.
[DETAIL]   IMPACT: Recovers disk space from accumulated temporary data.
[INFO]     Scanning: C:\Users\Chaitanya\AppData\Local\Temp
[INFO]     Found 13,670 files (4.28 GB)
[ACTION]   [DRY-RUN] Would delete 13,670 files (4.28 GB)
[SUCCESS]  Temp cleanup complete. Total recoverable: 8.55 GB
```

### Developer Tool Cache Cleanup

```
----------------------------------------------------------------------
  Developer Tool Cache Cleanup  [Risk: Low]
----------------------------------------------------------------------
[DETAIL]   WHY SAFE: Package manager caches can be rebuilt with next install.
[DETAIL]   IMPACT: Next package install may take slightly longer.
[INFO]     Scanning npm cache: C:\Users\Chaitanya\AppData\Local\npm-cache
[INFO]     Found 5,230 files (4.12 GB)
[ACTION]   [DRY-RUN] Would delete npm cache (4.12 GB)
[INFO]     Scanning NuGet cache: C:\Users\Chaitanya\.nuget\packages
[INFO]     Found 2,800 files (3.20 GB)
[ACTION]   [DRY-RUN] Would delete NuGet cache (3.20 GB)
[INFO]     Scanning pip cache: C:\Users\Chaitanya\AppData\Local\pip\cache
[INFO]     Found 1,382 files (1.24 GB)
[ACTION]   [DRY-RUN] Would delete pip cache (1.24 GB)
[SUCCESS]  Dev tool cache cleanup complete. Total: 8.56 GB
```

### Large File Finder (Read-Only)

```
----------------------------------------------------------------------
  Large File Finder (>500 MB)  [Risk: None (read-only)]
----------------------------------------------------------------------
[INFO]     This module is READ-ONLY. No files will be modified or deleted.
[DETAIL]   WHY: Identifies large files consuming disk space so you can decide.
[INFO]     Scanning user and common directories on C: for files >500 MB...

    LARGE FILES ON C:
    ----------------------------------------------------------------------
        25.50 GB  1d ago  C:\hiberfil.sys
        15.95 GB  492d ago  ...Collection(17 courses)-20241202T151456Z-001.zip
        15.33 GB  250d ago  ...Documents\Camtasia\Rec 01-08-2025.trec
         5.91 GB  236d ago  ...Downloads\ubuntu-24.04.3-desktop-amd64.iso
         5.70 GB  353d ago  ...Downloads\Win10_22H2_English_x64.iso
         4.56 GB  543d ago  ...Documents\Windows-10.iso
         4.35 GB  543d ago  ...Downloads\kali-linux-2024.3-live-amd64.iso
         4.14 GB  544d ago  ...Documents\ProPlusRetail.img
         4.00 GB  1d ago  C:\pagefile.sys
         3.33 GB  534d ago  ...Downloads\Compressed\[M.L.Engineer.Nano v2.zip
    ----------------------------------------------------------------------
    Total: 144.26 GB across 25 files

[DETAIL]   TIP: Review these files manually. Common culprits: VM images, ISOs, old backups.
```

### Scheduled Task Review (Read-Only)

```
----------------------------------------------------------------------
  Scheduled Task Audit  [Risk: None (read-only)]
----------------------------------------------------------------------
[INFO]     This module is READ-ONLY. No tasks will be modified.
[INFO]     Scanning for third-party scheduled tasks...

    THIRD-PARTY SCHEDULED TASKS
    ------------------------------------------------------------
    Task                              State    Next Run
    GoogleUpdateTaskUserCore          Ready    2026-04-09 08:15
    Adobe Acrobat Update Task         Ready    2026-04-09 12:00
    MicrosoftEdgeUpdateTaskUser       Ready    2026-04-09 06:30
    CCleaner Update                   Ready    2026-04-10 09:00

[INFO]     Found 4 third-party scheduled tasks. Review for unnecessary entries.
```

### Summary Report

```
======================================================================
  MAINTENANCE SUMMARY REPORT
======================================================================

  Duration        : 00:45
  Mode            : DRY-RUN (no changes made)
  Disk Freed      : 20.51 GB
  Files Processed : 44,736
  Errors          : 0
  Actions Logged  : 24

  Actions Taken:
  ------------------------------------------------------------------
  [OK] TempFiles          Delete         Temp Files       8.55 GB
  [OK] RecycleBin         Empty          Recycle Bin      332.41 MB
  [OK] BrowserCache       Delete         Browser Caches   1.12 GB
  [OK] ShaderCache        Delete         GPU Shaders      46.98 MB
  [OK] ThumbCacheCleanup  Delete         Thumb Cache      55.11 MB
  [OK] DevToolCaches      Delete         Dev Caches       8.56 GB
  [OK] AppCacheCleanup    Delete         App Caches       1.82 GB
  [OK] LargeFileFinder    Analyze        Large Files      --
  [OK] ScheduledTaskReview Analyze       Sched Tasks      --
  [SKIP] WindowsUpdate    Skip           Needs Admin
  [SKIP] EventLogs        Skip           Needs Admin
  ...

  Recommendations:
  ------------------------------------------------------------------
  * Re-run as Administrator for full functionality.
  * Schedule this tool monthly for ongoing maintenance.
  * Review startup items flagged by the Startup Analysis module.
  * Consider running Windows Disk Cleanup for deeper system cleanup.
  * Review 144.26 GB in large files identified by LargeFileFinder.

  Full log: C:\Users\Chaitanya\Documents\cleanup\logs\MaintenanceTool.log
======================================================================
```

## Interactive Menu (v4.0 with 32 Modules)

```
  Select modules to run:

    -- BASIC CLEANUP --
    [ 1] Temporary File Cleanup  (Risk: Low)
    [ 2] Windows Update Cache Cleanup [Requires Admin]  (Risk: Low)
    [ 3] Recycle Bin Cleanup  (Risk: Low)
    [ 4] Browser Cache Cleanup  (Risk: Low)
    [ 5] Old Event Log Cleanup [Requires Admin]  (Risk: Low)

    -- ADVANCED CLEANUP --
    [ 6] Prefetch Cache Cleanup [Requires Admin]  (Risk: Low)
    [ 7] Delivery Optimization Cache [Requires Admin]  (Risk: Low)
    [ 8] Old Windows Installation Cleanup [Requires Admin]  (Risk: Medium)
    [ 9] Crash Dump Cleanup [Requires Admin]  (Risk: Low)
    [10] Installer Patch Cache Cleanup [Requires Admin]  (Risk: Medium)
    [11] GPU Shader Cache Cleanup  (Risk: Low)
    [12] Thumbnail Cache Cleanup  (Risk: Low)
    [13] Windows Error Reporting Cleanup [Requires Admin]  (Risk: Low)
    [14] Diagnostic Log Archive Cleanup [Requires Admin]  (Risk: Low)
    [15] Windows Defender History Cleanup [Requires Admin]  (Risk: Low)
    [16] Windows Search Index Cleanup [Requires Admin]  (Risk: Low)
    [17] Shadow Copy Cleanup [Requires Admin]  (Risk: Medium)
    [18] Developer Tool Cache Cleanup  (Risk: Low)
    [19] Application Cache Cleanup  (Risk: Low)
    [20] .NET NGen Cache Cleanup [Requires Admin]  (Risk: Low)

    -- SYSTEM TOOLS --
    [21] Windows Disk Cleanup [Requires Admin]  (Risk: Low)
    [22] Component Store (WinSxS) Cleanup [Requires Admin]  (Risk: Low)
    [23] DNS Cache Flush [Requires Admin]  (Risk: Low)
    [24] Windows Store Cache Reset  (Risk: Low)
    [25] Font Cache Rebuild [Requires Admin]  (Risk: Low)

    -- ANALYSIS (READ-ONLY) --
    [26] Startup Program Analysis  (Risk: None (read-only))
    [27] Service Optimization Analysis  (Risk: None (read-only))
    [28] System Health Report  (Risk: None (read-only))
    [29] Network Configuration Analysis  (Risk: None (read-only))
    [30] Large File Finder (>500 MB)  (Risk: None (read-only))
    [31] Duplicate File Finder  (Risk: None (read-only))
    [32] Scheduled Task Audit  (Risk: None (read-only))

    [ A] Run ALL modules
    [ Q] Quit

  Enter selection (comma-separated, e.g. 1,3,5):
```
