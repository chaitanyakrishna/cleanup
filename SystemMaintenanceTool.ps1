<#
.SYNOPSIS
    System Maintenance Tool -- Auditable Windows cleanup & optimization utility.

.DESCRIPTION
    A production-quality, modular PowerShell tool for safely cleaning and optimizing
    Windows 10/11 workstations. Every action is logged, explained, and reversible where
    possible. Suitable for IT teams, developers, and power users managing
    for external audit.

.NOTES
    Version : 4.0.0
    Date    : 2026-04-08
    Author  : System Maintenance Tool Contributors
    License : MIT
    Requires: PowerShell 5.1+ / Windows 10 or 11
    Run As  : Administrator (recommended for full functionality)

.PARAMETER DryRun
    Preview all actions without making changes.

.PARAMETER Modules
    Comma-separated list of modules to run. Valid values:
    TempFiles, WindowsUpdate, RecycleBin, StartupAnalysis, DiskCleanup, ServiceAnalysis, BrowserCache, EventLogs

.PARAMETER SkipModules
    Comma-separated list of modules to skip.

.PARAMETER NonInteractive
    Run without confirmation prompts (uses safe defaults).

.PARAMETER LogPath
    Custom path for the log file. Defaults to script directory.

.EXAMPLE
    .\SystemMaintenanceTool.ps1 -DryRun
    Preview all cleanup actions without making changes.

.EXAMPLE
    .\SystemMaintenanceTool.ps1 -Modules TempFiles,RecycleBin
    Run only temp file and recycle bin cleanup.

.EXAMPLE
    .\SystemMaintenanceTool.ps1 -SkipModules StartupAnalysis -NonInteractive
    Run all modules except startup analysis, no prompts.
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$DryRun,

    [ValidateSet('TempFiles','WindowsUpdate','RecycleBin','StartupAnalysis',
                 'DiskCleanup','ServiceAnalysis','BrowserCache','EventLogs',
                 'PrefetchCleanup','DeliveryOptimization','WindowsOldCleanup',
                 'CrashDumps','InstallerCleanup','ShaderCache','ThumbCacheCleanup',
                 'ComponentStoreCleanup','DNSCacheFlush','WindowsStoreCache',
                 'SystemHealthCheck','NetworkAnalysis',
                 'ErrorReporting','WindowsLogFiles','DefenderCache',
                 'SearchIndexCleanup','ShadowCopyCleanup','DevToolCaches',
                 'AppCacheCleanup','FontCacheRebuild','DotNetCleanup',
                 'LargeFileFinder','DuplicateFileFinder','ScheduledTaskReview',
                 'WindowsPrivacyCleanup','BrowserPrivacyCleanup','OfficeCleanup',
                 'CloudStorageCleanup','AdobeCleanup','JavaCleanup',
                 'ChkdskFragments','IISLogCleanup','FreeSpaceWiper','RestorePointAnalysis')]
    [string[]]$Modules,

    [ValidateSet('TempFiles','WindowsUpdate','RecycleBin','StartupAnalysis',
                 'DiskCleanup','ServiceAnalysis','BrowserCache','EventLogs',
                 'PrefetchCleanup','DeliveryOptimization','WindowsOldCleanup',
                 'CrashDumps','InstallerCleanup','ShaderCache','ThumbCacheCleanup',
                 'ComponentStoreCleanup','DNSCacheFlush','WindowsStoreCache',
                 'SystemHealthCheck','NetworkAnalysis',
                 'ErrorReporting','WindowsLogFiles','DefenderCache',
                 'SearchIndexCleanup','ShadowCopyCleanup','DevToolCaches',
                 'AppCacheCleanup','FontCacheRebuild','DotNetCleanup',
                 'LargeFileFinder','DuplicateFileFinder','ScheduledTaskReview',
                 'WindowsPrivacyCleanup','BrowserPrivacyCleanup','OfficeCleanup',
                 'CloudStorageCleanup','AdobeCleanup','JavaCleanup',
                 'ChkdskFragments','IISLogCleanup','FreeSpaceWiper','RestorePointAnalysis')]
    [string[]]$SkipModules,

    [switch]$NonInteractive,

    [string]$LogPath,

    [switch]$Sound,

    [switch]$RetroUI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Crash logging trap -- captures fatal errors to file (critical for exe builds)
trap {
    $crashFile = Join-Path ([System.IO.Path]::GetTempPath()) 'SystemMaintenanceTool_crash.log'
    $msg = "CRASH at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n$($_.Exception.Message)`n$($_.ScriptStackTrace)`n$($_.InvocationInfo.PositionMessage)"
    [System.IO.File]::AppendAllText($crashFile, "$msg`n---`n")
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Crash log: $crashFile" -ForegroundColor Yellow
    Write-Host "Press Enter to exit..." -ForegroundColor Yellow
    try { $null = Read-Host } catch {}
    break
}

# -----------------------------------------------------------------------------
# SECTION 1 -- CONFIGURATION & GLOBALS
# -----------------------------------------------------------------------------

$Script:Version = '6.0.0'
$Script:StartTime = Get-Date
$Script:ScriptRoot = $PSScriptRoot
if (-not $Script:ScriptRoot) {
    try { $Script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path } catch {}
}
if (-not $Script:ScriptRoot) {
    try { $Script:ScriptRoot = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {}
}
if (-not $Script:ScriptRoot) { $Script:ScriptRoot = (Get-Location).Path }

# Log file setup
if (-not $LogPath) {
    $LogPath = Join-Path $Script:ScriptRoot "logs"
}
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}
$Script:LogFile = Join-Path $LogPath ("MaintenanceTool_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

# -----------------------------------------------------------------------------
# RESOURCE MANAGEMENT -- CPU, RAM, GC tuning for smooth execution
# -----------------------------------------------------------------------------

# Detect system resources
$Script:CpuCores   = [Environment]::ProcessorCount
$Script:TotalRAM_MB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1MB, 0)
$Script:AvailRAM_MB = [math]::Round((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).FreePhysicalMemory / 1KB, 0)

# Set process priority to BelowNormal so cleanup never starves user apps
try {
    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $currentProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
    $Script:ProcessPriority = 'BelowNormal'
} catch {
    $Script:ProcessPriority = 'Normal (default)'
}

# Reserve cores -- on 4+ core systems, limit affinity to leave 1 core free for the OS/user
try {
    $proc = [System.Diagnostics.Process]::GetCurrentProcess()
    if ($Script:CpuCores -ge 4) {
        # Use all cores except the last one (bitmask: e.g. 8 cores => 0xFF => leave core 7 => 0x7F)
        $affinityMask = [IntPtr]((1 -shl ($Script:CpuCores - 1)) - 1)
        $proc.ProcessorAffinity = $affinityMask
        $Script:CoresAllocated = $Script:CpuCores - 1
    } else {
        $Script:CoresAllocated = $Script:CpuCores
    }
} catch {
    $Script:CoresAllocated = $Script:CpuCores
}

# Configure .NET garbage collector for workstation mode (lower latency, periodic collection)
try {
    [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = [System.Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
} catch { }

# Memory pressure helper -- forces GC when working set grows too large
function Invoke-MemoryRelief {
    <#
    .SYNOPSIS
        Collects garbage and compacts LOH when memory usage exceeds threshold.
        Called between modules to prevent runaway memory in long scan sessions.
    #>
    param([int]$ThresholdMB = 512)
    try {
        $ws = [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64
        if ($ws -gt ($ThresholdMB * 1MB)) {
            [System.GC]::Collect(2, [System.GCCollectionMode]::Optimized)
            [System.GC]::WaitForPendingFinalizers()
        }
    } catch { }
}

# Tracking -- every action and its outcome is recorded here
$Script:ActionLog = [System.Collections.Generic.List[PSCustomObject]]::new()
$Script:TotalBytesFreed = 0
$Script:TotalFilesRemoved = 0
$Script:TotalErrors = 0
$Script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

# All available modules with metadata
$Script:AllModules = [ordered]@{
    # ── BASIC CLEANUP ──
    'TempFiles'             = @{ Name = 'Temporary File Cleanup';       RequiresAdmin = $false; Risk = 'Low';               Category = 'Basic' }
    'WindowsUpdate'         = @{ Name = 'Windows Update Cache';         RequiresAdmin = $true;  Risk = 'Low';               Category = 'Basic' }
    'RecycleBin'            = @{ Name = 'Recycle Bin Cleanup';          RequiresAdmin = $false; Risk = 'Low';               Category = 'Basic' }
    'BrowserCache'          = @{ Name = 'Browser Cache Cleanup';        RequiresAdmin = $false; Risk = 'Low';               Category = 'Basic' }
    'EventLogs'             = @{ Name = 'Old Event Log Cleanup';        RequiresAdmin = $true;  Risk = 'Low';               Category = 'Basic' }
    # ── ADVANCED CLEANUP ──
    'PrefetchCleanup'       = @{ Name = 'Prefetch Cache Cleanup';       RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'DeliveryOptimization'  = @{ Name = 'Delivery Optimization Cache';  RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'WindowsOldCleanup'     = @{ Name = 'Old Windows Installation';     RequiresAdmin = $true;  Risk = 'Medium';            Category = 'Advanced' }
    'CrashDumps'            = @{ Name = 'Crash Dump Cleanup';           RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'InstallerCleanup'      = @{ Name = 'Installer Patch Cache';        RequiresAdmin = $true;  Risk = 'Medium';            Category = 'Advanced' }
    'ShaderCache'           = @{ Name = 'GPU Shader Cache Cleanup';     RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'ThumbCacheCleanup'     = @{ Name = 'Thumbnail Cache Cleanup';      RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'ComponentStoreCleanup' = @{ Name = 'Component Store (WinSxS)';     RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'ErrorReporting'        = @{ Name = 'Windows Error Reports';        RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'WindowsLogFiles'       = @{ Name = 'Diagnostic Log Archives';      RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'DefenderCache'         = @{ Name = 'Defender History Cache';        RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'SearchIndexCleanup'    = @{ Name = 'Search Index Rebuild';          RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'ShadowCopyCleanup'     = @{ Name = 'Volume Shadow Copies';         RequiresAdmin = $true;  Risk = 'Medium';            Category = 'Advanced' }
    'DevToolCaches'         = @{ Name = 'Developer Tool Caches';        RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'AppCacheCleanup'       = @{ Name = 'Application Cache Cleanup';    RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'DotNetCleanup'         = @{ Name = '.NET Native Image Cache';      RequiresAdmin = $true;  Risk = 'Medium';            Category = 'Advanced' }
    # ── SYSTEM TOOLS ──
    'DiskCleanup'           = @{ Name = 'Windows Disk Cleanup';         RequiresAdmin = $true;  Risk = 'Low';               Category = 'Tools' }
    'DNSCacheFlush'         = @{ Name = 'DNS Cache Flush';              RequiresAdmin = $true;  Risk = 'Low';               Category = 'Tools' }
    'WindowsStoreCache'     = @{ Name = 'Windows Store Cache Reset';    RequiresAdmin = $false; Risk = 'Low';               Category = 'Tools' }
    'FontCacheRebuild'      = @{ Name = 'Font Cache Rebuild';           RequiresAdmin = $true;  Risk = 'Low';               Category = 'Tools' }
    # ── ANALYSIS (READ-ONLY) ──
    'StartupAnalysis'       = @{ Name = 'Startup Program Analysis';     RequiresAdmin = $false; Risk = 'None (read-only)';  Category = 'Analysis' }
    'ServiceAnalysis'       = @{ Name = 'Service Optimization Analysis';RequiresAdmin = $false; Risk = 'None (read-only)';  Category = 'Analysis' }
    'SystemHealthCheck'     = @{ Name = 'System Health Report';         RequiresAdmin = $false; Risk = 'None (read-only)';  Category = 'Analysis' }
    'NetworkAnalysis'       = @{ Name = 'Network Diagnostics';          RequiresAdmin = $false; Risk = 'None (read-only)';  Category = 'Analysis' }
    'LargeFileFinder'       = @{ Name = 'Large File Finder (>500MB)';   RequiresAdmin = $false; Risk = 'None (read-only)';  Category = 'Analysis' }
    'DuplicateFileFinder'   = @{ Name = 'Duplicate File Finder';        RequiresAdmin = $false; Risk = 'None (read-only)';  Category = 'Analysis' }
    'ScheduledTaskReview'   = @{ Name = 'Scheduled Task Review';        RequiresAdmin = $false; Risk = 'None (read-only)';  Category = 'Analysis' }
    # -- PRIVACY --
    'WindowsPrivacyCleanup' = @{ Name = 'Windows Privacy Cleanup';      RequiresAdmin = $false; Risk = 'Low';               Category = 'Privacy' }
    'BrowserPrivacyCleanup' = @{ Name = 'Browser Privacy Cleanup';      RequiresAdmin = $false; Risk = 'Medium';            Category = 'Privacy' }
    # -- ADVANCED (additions) --
    'OfficeCleanup'         = @{ Name = 'Office Temp & Cache Cleanup';  RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'CloudStorageCleanup'   = @{ Name = 'Cloud Storage Cache Cleanup';  RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'AdobeCleanup'          = @{ Name = 'Adobe Product Cache Cleanup';  RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'JavaCleanup'           = @{ Name = 'Java Cache Cleanup';           RequiresAdmin = $false; Risk = 'Low';               Category = 'Advanced' }
    'ChkdskFragments'       = @{ Name = 'Chkdsk File Fragments';        RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    'IISLogCleanup'         = @{ Name = 'IIS Log File Cleanup';         RequiresAdmin = $true;  Risk = 'Low';               Category = 'Advanced' }
    # -- TOOLS (addition) --
    'FreeSpaceWiper'        = @{ Name = 'Free Space Secure Wipe';       RequiresAdmin = $true;  Risk = 'Medium';            Category = 'Tools' }
    # -- ANALYSIS (addition) --
    'RestorePointAnalysis'  = @{ Name = 'Restore Point Analysis';       RequiresAdmin = $true;  Risk = 'None (read-only)';  Category = 'Analysis' }
}

# -----------------------------------------------------------------------------
# SECTION 2 -- OUTPUT & LOGGING FUNCTIONS
# -----------------------------------------------------------------------------

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped entry to the log file and optionally to the console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','ACTION','SUCCESS','WARNING','ERROR','SKIP','SECTION','DETAIL')]
        [string]$Level = 'INFO',
        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    # Append to log file (thread-safe via mutex would be overkill for sequential execution)
    try {
        Add-Content -Path $Script:LogFile -Value $logEntry -Encoding UTF8
    } catch {
        # Fallback: write to temp if main log fails
        $fallback = Join-Path $env:TEMP "MaintenanceTool_fallback.log"
        Add-Content -Path $fallback -Value $logEntry -Encoding UTF8
    }

    if ($NoConsole) { return }

    # Color-coded console output
    $colors = @{
        'INFO'    = 'Cyan'
        'ACTION'  = 'Yellow'
        'SUCCESS' = 'Green'
        'WARNING' = 'DarkYellow'
        'ERROR'   = 'Red'
        'SKIP'    = 'DarkGray'
        'SECTION' = 'White'
        'DETAIL'  = 'Gray'
    }
    $prefix = "[$Level]".PadRight(10)
    Write-Host "$prefix " -ForegroundColor $colors[$Level] -NoNewline
    Write-Host $Message
}

function Write-SectionHeader {
    <#
    .SYNOPSIS
        Prints a clearly-separated section header for each module.
    #>
    param([string]$Title, [string]$Risk = 'Low')

    $separator = [string]::new([char]0x2500, 70)
    Write-Host ""
    Write-Host $separator -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor White -NoNewline
    Write-Host "  [Risk: $Risk]" -ForegroundColor $(if ($Risk -eq 'None (read-only)') { 'Green' } else { 'Yellow' })
    Write-Host $separator -ForegroundColor DarkCyan
    Write-Log -Message "=== MODULE: $Title (Risk: $Risk) ===" -Level SECTION -NoConsole
}

function Write-Banner {
    <#
    .SYNOPSIS
        Prints the tool banner at startup.
    #>
    $banner = @"

    +==============================================================+
    |       System Maintenance Tool  v$($Script:Version)                    |
    |       Auditable - Safe - Transparent                         |
    +==============================================================+
"@
    Write-Host $banner -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "    *** DRY-RUN MODE -- No changes will be made ***" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "    Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "    Computer : $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "    User     : $env:USERNAME" -ForegroundColor Gray
    Write-Host "    Admin    : $Script:IsAdmin" -ForegroundColor $(if ($Script:IsAdmin) { 'Green' } else { 'Yellow' })
    Write-Host "    CPU      : $Script:CoresAllocated / $Script:CpuCores cores allocated  |  Priority: $Script:ProcessPriority" -ForegroundColor Gray
    Write-Host "    RAM      : $('{0:N0}' -f $Script:AvailRAM_MB) MB free / $('{0:N0}' -f $Script:TotalRAM_MB) MB total" -ForegroundColor Gray
    Write-Host "    Log File : $Script:LogFile" -ForegroundColor Gray
    Write-Host ""
}

function Record-Action {
    <#
    .SYNOPSIS
        Records an action to the internal audit trail.
    #>
    param(
        [string]$Module,
        [string]$Action,
        [string]$Target,
        [string]$Result,
        [long]$BytesFreed = 0,
        [int]$FilesAffected = 0
    )

    $Script:ActionLog.Add([PSCustomObject]@{
        Timestamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Module        = $Module
        Action        = $Action
        Target        = $Target
        Result        = $Result
        BytesFreed    = $BytesFreed
        FilesAffected = $FilesAffected
        DryRun        = [bool]$DryRun
    })

    $Script:TotalBytesFreed += $BytesFreed
    $Script:TotalFilesRemoved += $FilesAffected
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Converts bytes to a human-readable string.
    #>
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Write-ProgressBar {
    <#
    .SYNOPSIS
        Renders a compact inline progress bar to the console.
    .PARAMETER Current
        Current step number (1-based).
    .PARAMETER Total
        Total number of steps.
    .PARAMETER Activity
        Short label for the current step.
    .PARAMETER BarWidth
        Character width of the progress bar. Default 30.
    #>
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity = '',
        [int]$BarWidth = 30
    )

    $pct = [math]::Round(($Current / $Total) * 100)
    $filled = [math]::Round(($Current / $Total) * $BarWidth)
    $empty  = $BarWidth - $filled
    $bar    = ([string]::new('#', $filled)) + ([string]::new('-', $empty))

    # Pad activity to fixed width to overwrite previous text
    $label = $Activity
    if ($label.Length -gt 28) { $label = $label.Substring(0, 25) + '...' }
    $label = $label.PadRight(28)

    $line = "`r  [$bar] $pct% ($Current/$Total) $label"

    Write-Host $line -ForegroundColor Cyan -NoNewline

    # Print newline on completion
    if ($Current -ge $Total) { Write-Host "" }
}

function Play-RetroSound {
    <#
    .SYNOPSIS
        Plays retro-style beep sounds when -Sound switch is enabled.
    #>
    param(
        [ValidateSet('ScanStart','ScanTick','ScanComplete','ActionStart','Success','Error','Warning','Complete','Welcome')]
        [string]$Type
    )
    if (-not $Sound) { return }

    try {
        switch ($Type) {
            'Welcome'      { [Console]::Beep(523, 100); Start-Sleep -Milliseconds 50; [Console]::Beep(659, 100); Start-Sleep -Milliseconds 50; [Console]::Beep(784, 200) }
            'ScanStart'    { [Console]::Beep(440, 150); Start-Sleep -Milliseconds 30; [Console]::Beep(550, 150) }
            'ScanTick'     { [Console]::Beep(800, 30) }
            'ScanComplete' { [Console]::Beep(660, 100); Start-Sleep -Milliseconds 50; [Console]::Beep(880, 200) }
            'ActionStart'  { [Console]::Beep(440, 80) }
            'Success'      { [Console]::Beep(523, 80); Start-Sleep -Milliseconds 30; [Console]::Beep(659, 80); Start-Sleep -Milliseconds 30; [Console]::Beep(784, 150) }
            'Error'        { [Console]::Beep(200, 300); Start-Sleep -Milliseconds 50; [Console]::Beep(150, 300) }
            'Warning'      { [Console]::Beep(350, 150); Start-Sleep -Milliseconds 50; [Console]::Beep(300, 150) }
            'Complete'     {
                # Victory fanfare (short retro jingle)
                $notes = @(
                    @(523, 80), @(523, 80), @(523, 80), @(523, 300),
                    @(415, 300), @(466, 300), @(523, 200),
                    @(466, 80), @(523, 400)
                )
                foreach ($n in $notes) {
                    [Console]::Beep($n[0], $n[1])
                    Start-Sleep -Milliseconds 30
                }
            }
        }
    } catch {
        # Silently ignore if beep is not available (e.g., no speaker)
    }
}

function Request-Confirmation {
    <#
    .SYNOPSIS
        Prompts the user for confirmation before a risky action.
        Returns $true in NonInteractive or DryRun mode.
    #>
    param([string]$Message)

    if ($DryRun) { return $true }   # dry-run shows what would happen
    if ($NonInteractive) { return $true }

    Write-Host ""
    Write-Host "    ? $Message" -ForegroundColor Yellow -NoNewline
    Write-Host " [Y/n] " -ForegroundColor White -NoNewline
    $response = Read-Host
    return ($response -eq '' -or $response -match '^[Yy]')
}

# -----------------------------------------------------------------------------
# SECTION 3 -- UTILITY HELPERS
# -----------------------------------------------------------------------------

function Get-FolderSize {
    <#
    .SYNOPSIS
        Safely calculates the total size of files in a folder.
    #>
    param([string]$Path, [switch]$Recurse)

    if (-not (Test-Path $Path)) { return 0 }

    try {
        $files = if ($Recurse) {
            Get-ChildItem -Path $Path -File -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -Path $Path -File -Force -ErrorAction SilentlyContinue
        }
        return ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    } catch {
        return 0
    }
}

function Remove-SafeFiles {
    <#
    .SYNOPSIS
        Removes files from a path with full logging and error handling.
        Skips locked files gracefully.
    #>
    param(
        [string]$Path,
        [string]$ModuleName,
        [string]$Description,
        [int]$MinAgeDays = 0,
        [switch]$Recurse
    )

    if (-not (Test-Path $Path)) {
        Write-Log "Path does not exist: $Path" -Level SKIP
        return @{ BytesFreed = 0; FilesRemoved = 0; Errors = 0 }
    }

    $getParams = @{
        Path        = $Path
        File        = $true
        Force       = $true
        ErrorAction = 'SilentlyContinue'
    }
    if ($Recurse) { $getParams['Recurse'] = $true }

    $files = Get-ChildItem @getParams

    if ($MinAgeDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$MinAgeDays)
        $files = $files | Where-Object { $_.LastWriteTime -lt $cutoff }
    }

    if (-not $files -or $files.Count -eq 0) {
        Write-Log "No eligible files found in: $Path" -Level SKIP
        return @{ BytesFreed = 0; FilesRemoved = 0; Errors = 0 }
    }

    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
    $fileCount = $files.Count

    Write-Log "Found $fileCount files ($(Format-FileSize $totalSize)) in $Path" -Level INFO
    Write-Log "Reason: $Description" -Level DETAIL

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $fileCount files ($(Format-FileSize $totalSize))" -Level ACTION
        Record-Action -Module $ModuleName -Action 'WouldDelete' -Target $Path `
                      -Result 'DryRun' -BytesFreed 0 -FilesAffected 0
        return @{ BytesFreed = $totalSize; FilesRemoved = $fileCount; Errors = 0 }
    }

    $freed = [long]0
    $removed = 0
    $errors = 0

    foreach ($file in $files) {
        try {
            $size = $file.Length
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            $freed += $size
            $removed++
        } catch {
            # File is locked or in use -- skip it silently (this is expected)
            $errors++
            Write-Log "Skipped (in use): $($file.FullName)" -Level DETAIL -NoConsole
        }
    }

    Write-Log "Deleted $removed/$fileCount files, freed $(Format-FileSize $freed)" -Level SUCCESS
    if ($errors -gt 0) {
        Write-Log "$errors files skipped (locked/in-use -- this is normal)" -Level WARNING
    }

    Record-Action -Module $ModuleName -Action 'Delete' -Target $Path `
                  -Result 'Completed' -BytesFreed $freed -FilesAffected $removed

    return @{ BytesFreed = $freed; FilesRemoved = $removed; Errors = $errors }
}

# -----------------------------------------------------------------------------
# SECTION 4 -- CLEANUP MODULES
# -----------------------------------------------------------------------------

function Invoke-TempFileCleanup {
    <#
    .SYNOPSIS
        Cleans Windows and user temp directories.
    .DESCRIPTION
        Removes files older than 2 days from standard temp locations. These are
        transient files created by applications and Windows that are safe to remove
        once they are no longer actively in use (locked files are skipped).
    #>
    Write-SectionHeader -Title 'Temporary File Cleanup' -Risk 'Low'

    Write-Log "WHY SAFE: Temp files are transient by design. Locked files are skipped." -Level DETAIL
    Write-Log "IMPACT: Recovers disk space from accumulated temporary data." -Level DETAIL

    $targets = @(
        @{ Path = $env:TEMP;             Desc = 'User temp directory -- application scratch files' }
        @{ Path = "$env:WINDIR\Temp";     Desc = 'System temp directory -- OS and service scratch files' }
        @{ Path = "$env:LOCALAPPDATA\Temp"; Desc = 'Local AppData temp -- per-user application temp files' }
    )

    $moduleTotalFreed = [long]0

    foreach ($target in $targets) {
        if (-not (Test-Path $target.Path)) { continue }

        Write-Log "Scanning: $($target.Path)" -Level INFO
        $result = Remove-SafeFiles -Path $target.Path -ModuleName 'TempFiles' `
                    -Description $target.Desc -MinAgeDays 2 -Recurse
        $moduleTotalFreed += $result.BytesFreed
    }

    # Clean empty subdirectories in temp folders
    foreach ($target in $targets) {
        if (-not (Test-Path $target.Path)) { continue }
        try {
            $emptyDirs = Get-ChildItem -Path $target.Path -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                         Where-Object { @(Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 }

            if ($emptyDirs) {
                $count = $emptyDirs.Count
                if (-not $DryRun) {
                    $emptyDirs | Remove-Item -Force -ErrorAction SilentlyContinue
                }
                Write-Log "Removed $count empty subdirectories from $($target.Path)" -Level DETAIL
            }
        } catch {
            # Non-critical -- skip
        }
    }

    Write-Log "Temp cleanup complete. Total recoverable: $(Format-FileSize $moduleTotalFreed)" -Level SUCCESS
}

function Invoke-WindowsUpdateCleanup {
    <#
    .SYNOPSIS
        Cleans the Windows Update download cache.
    .DESCRIPTION
        Removes cached update files from C:\Windows\SoftwareDistribution\Download.
        These are installation packages that Windows retains after updates are applied.
        Requires administrator privileges. The Windows Update service is stopped before
        cleanup and restarted afterward.
    #>
    Write-SectionHeader -Title 'Windows Update Cache Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Requires administrator privileges." -Level WARNING
        Record-Action -Module 'WindowsUpdate' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    $wuPath = "$env:WINDIR\SoftwareDistribution\Download"

    if (-not (Test-Path $wuPath)) {
        Write-Log "Windows Update cache path not found." -Level SKIP
        return
    }

    $cacheSize = Get-FolderSize -Path $wuPath -Recurse

    Write-Log "WHY SAFE: These are already-installed update packages cached for rollback." -Level DETAIL
    Write-Log "IMPACT: Frees $(Format-FileSize $cacheSize) of disk space." -Level DETAIL
    Write-Log "ROLLBACK: Windows will re-download updates if needed." -Level DETAIL

    if ($cacheSize -lt 1MB) {
        Write-Log "Cache is under 1 MB -- skipping (not worth the service restart)." -Level SKIP
        return
    }

    if (-not (Request-Confirmation "Delete $(Format-FileSize $cacheSize) of Windows Update cache?")) {
        Write-Log "User declined Windows Update cache cleanup." -Level SKIP
        return
    }

    if (-not $DryRun) {
        Write-Log "Stopping Windows Update service..." -Level ACTION
        try {
            Stop-Service -Name wuauserv -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        } catch {
            Write-Log "Could not stop Windows Update service: $($_.Exception.Message)" -Level ERROR
            $Script:TotalErrors++
            return
        }
    }

    $result = Remove-SafeFiles -Path $wuPath -ModuleName 'WindowsUpdate' `
                -Description 'Cached update installation packages' -Recurse

    if (-not $DryRun) {
        Write-Log "Restarting Windows Update service..." -Level ACTION
        try {
            Start-Service -Name wuauserv -ErrorAction Stop
            Write-Log "Windows Update service restarted successfully." -Level SUCCESS
        } catch {
            Write-Log "WARNING: Could not restart wuauserv. Run 'Start-Service wuauserv' manually." -Level ERROR
            $Script:TotalErrors++
        }
    }
}

function Invoke-RecycleBinCleanup {
    <#
    .SYNOPSIS
        Empties the Recycle Bin for the current user.
    .DESCRIPTION
        Files in the Recycle Bin have already been deleted by the user and are only
        retained for recovery purposes. This frees the space they occupy.
    #>
    Write-SectionHeader -Title 'Recycle Bin Cleanup' -Risk 'Low'

    Write-Log "WHY SAFE: Recycle Bin contains files the user has already deleted." -Level DETAIL
    Write-Log "IMPACT: Frees disk space from pending permanent deletions." -Level DETAIL

    # Estimate recycle bin size via Shell COM object
    $shell = New-Object -ComObject Shell.Application
    $recycleBin = $shell.NameSpace(0x0A)
    $items = $recycleBin.Items()
    $itemCount = $items.Count

    if ($itemCount -eq 0) {
        Write-Log "Recycle Bin is already empty." -Level SKIP
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        return
    }

    # Estimate size
    $totalSize = [long]0
    foreach ($item in $items) {
        try { $totalSize += $recycleBin.GetDetailsOf($item, 2) -replace '[^\d]','' } catch {}
    }

    Write-Log "Recycle Bin contains $itemCount item(s)." -Level INFO

    if (-not (Request-Confirmation "Permanently empty the Recycle Bin ($($itemCount) items)?")) {
        Write-Log "User declined Recycle Bin cleanup." -Level SKIP
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        return
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would empty Recycle Bin ($itemCount items)." -Level ACTION
        Record-Action -Module 'RecycleBin' -Action 'WouldEmpty' -Target 'RecycleBin' `
                      -Result 'DryRun' -FilesAffected $itemCount
    } else {
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Log "Recycle Bin emptied successfully ($itemCount items removed)." -Level SUCCESS
            Record-Action -Module 'RecycleBin' -Action 'Empty' -Target 'RecycleBin' `
                          -Result 'Completed' -FilesAffected $itemCount
        } catch {
            Write-Log "Error emptying Recycle Bin: $($_.Exception.Message)" -Level ERROR
            $Script:TotalErrors++
        }
    }

    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
}

function Invoke-StartupAnalysis {
    <#
    .SYNOPSIS
        Analyzes startup programs and provides recommendations (READ-ONLY).
    .DESCRIPTION
        Lists all programs configured to run at startup, their publisher, and estimated
        impact. This module does NOT disable anything -- it only reports findings with
        recommendations for manual review.
    #>
    Write-SectionHeader -Title 'Startup Program Analysis' -Risk 'None (read-only)'

    Write-Log "This module is READ-ONLY. No changes will be made." -Level INFO
    Write-Log "WHY: Startup items affect boot time. Review helps identify unnecessary load." -Level DETAIL

    $startupItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Registry Run keys (HKCU + HKLM)
    $regPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($regPath in $regPaths) {
        if (-not (Test-Path $regPath)) { continue }
        try {
            $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            $props.PSObject.Properties | Where-Object {
                $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')
            } | ForEach-Object {
                $startupItems.Add([PSCustomObject]@{
                    Name     = $_.Name
                    Command  = $_.Value
                    Source   = $regPath
                    Type     = 'Registry'
                })
            }
        } catch { }
    }

    # Startup folder
    $startupFolder = [Environment]::GetFolderPath('Startup')
    if (Test-Path $startupFolder) {
        Get-ChildItem -Path $startupFolder -File -ErrorAction SilentlyContinue | ForEach-Object {
            $startupItems.Add([PSCustomObject]@{
                Name     = $_.BaseName
                Command  = $_.FullName
                Source   = $startupFolder
                Type     = 'StartupFolder'
            })
        }
    }

    # Scheduled tasks that run at logon
    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Ready' -and $_.Triggers } |
            ForEach-Object {
                $hasLogonTrigger = $_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }
                if ($hasLogonTrigger) {
                    $startupItems.Add([PSCustomObject]@{
                        Name     = $_.TaskName
                        Command  = ($_.Actions | Select-Object -First 1).Execute
                        Source   = $_.TaskPath
                        Type     = 'ScheduledTask'
                    })
                }
            }
    } catch { }

    if ($startupItems.Count -eq 0) {
        Write-Log "No startup items found." -Level INFO
        return
    }

    Write-Log "Found $($startupItems.Count) startup item(s):" -Level INFO
    Write-Host ""

    # Known unnecessary/bloatware startup entries for flagging
    $flagPatterns = @(
        '*Update*Helper*', '*Updater*', '*iTunesHelper*', '*Spotify*',
        '*Discord*Update*', '*Adobe*ARM*', '*CCleaner*', '*OneDrive*',
        '*Teams*Update*', '*Skype*Bridge*', '*GoogleUpdate*'
    )

    foreach ($item in $startupItems) {
        $isFlagged = $false
        foreach ($pattern in $flagPatterns) {
            if ($item.Name -like $pattern -or $item.Command -like $pattern) {
                $isFlagged = $true
                break
            }
        }

        $icon = if ($isFlagged) { '!' } else { ' ' }
        $color = if ($isFlagged) { 'Yellow' } else { 'Gray' }

        Write-Host "    [$icon] " -ForegroundColor $color -NoNewline
        Write-Host "$($item.Name)" -ForegroundColor White -NoNewline
        Write-Host " ($($item.Type))" -ForegroundColor DarkGray
        Write-Host "        $($item.Command)" -ForegroundColor DarkGray

        if ($isFlagged) {
            Write-Host "        >> RECOMMENDATION: Review if this needs to run at startup." -ForegroundColor Yellow
        }
    }

    $flaggedCount = ($startupItems | Where-Object {
        $n = $_
        $flagPatterns | Where-Object { $n.Name -like $_ -or $n.Command -like $_ }
    }).Count

    Write-Host ""
    Write-Log "$($startupItems.Count) startup items analyzed. $flaggedCount flagged for review." -Level SUCCESS
    Write-Log "TIP: Use Task Manager > Startup tab to disable unnecessary items." -Level DETAIL

    Record-Action -Module 'StartupAnalysis' -Action 'Analyze' -Target 'Startup Items' `
                  -Result "Found $($startupItems.Count), flagged $flaggedCount"
}

function Invoke-DiskCleanup {
    <#
    .SYNOPSIS
        Runs the built-in Windows Disk Cleanup utility (cleanmgr).
    .DESCRIPTION
        Invokes the native Windows Disk Cleanup tool with pre-configured options.
        This is Microsoft's own cleanup utility and is fully supported.
        Requires administrator privileges for system-wide cleanup.
    #>
    Write-SectionHeader -Title 'Windows Disk Cleanup (Built-in)' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: System-wide disk cleanup requires administrator privileges." -Level WARNING
        Write-Log "TIP: You can run 'cleanmgr' manually from an elevated prompt." -Level DETAIL
        Record-Action -Module 'DiskCleanup' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    Write-Log "WHY SAFE: Uses Microsoft's built-in cleanmgr.exe utility." -Level DETAIL
    Write-Log "IMPACT: Removes system caches, old Windows installations, error reports." -Level DETAIL

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would invoke Windows Disk Cleanup (cleanmgr /sagerun:1)." -Level ACTION
        Record-Action -Module 'DiskCleanup' -Action 'WouldRun' -Target 'cleanmgr' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Run Windows Disk Cleanup? This may take several minutes.")) {
        Write-Log "User declined disk cleanup." -Level SKIP
        return
    }

    # Pre-configure Disk Cleanup categories via registry
    Write-Log "Configuring cleanup categories..." -Level ACTION
    $sagePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $categories = @(
        'Temporary Files',
        'Temporary Setup Files',
        'Old ChkDsk Files',
        'Setup Log Files',
        'System error memory dump files',
        'System error minidump files',
        'Windows Error Reporting Files',
        'Thumbnail Cache',
        'Delivery Optimization Files',
        'Device Driver Packages'
    )

    foreach ($cat in $categories) {
        $catPath = Join-Path $sagePath $cat
        if (Test-Path $catPath) {
            try {
                Set-ItemProperty -Path $catPath -Name 'StateFlags0001' -Value 2 -Type DWord -ErrorAction SilentlyContinue
            } catch { }
        }
    }

    Write-Log "Running cleanmgr (this may take a few minutes)..." -Level ACTION
    try {
        $process = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -eq 0) {
            Write-Log "Windows Disk Cleanup completed successfully." -Level SUCCESS
        } else {
            Write-Log "Disk Cleanup exited with code $($process.ExitCode)." -Level WARNING
        }
        Record-Action -Module 'DiskCleanup' -Action 'Run' -Target 'cleanmgr' -Result 'Completed'
    } catch {
        Write-Log "Error running Disk Cleanup: $($_.Exception.Message)" -Level ERROR
        $Script:TotalErrors++
    }
}

function Invoke-ServiceAnalysis {
    <#
    .SYNOPSIS
        Analyzes running services and provides optimization suggestions (READ-ONLY).
    .DESCRIPTION
        Identifies services that are running but may not be needed in a typical
        workstation configuration. Provides recommendations -- does NOT disable anything.
    #>
    Write-SectionHeader -Title 'Service Optimization Analysis' -Risk 'None (read-only)'

    Write-Log "This module is READ-ONLY. No services will be stopped or disabled." -Level INFO
    Write-Log "WHY: Unnecessary services consume memory and may slow boot." -Level DETAIL

    # Services that are commonly unnecessary on managed workstations
    $reviewCandidates = @{
        'DiagTrack'          = 'Connected User Experiences and Telemetry -- sends diagnostic data to Microsoft.'
        'dmwappushservice'   = 'Device Management WAP Push -- used for MDM push messaging.'
        'MapsBroker'         = 'Downloaded Maps Manager -- downloads offline map data.'
        'lfsvc'              = 'Geolocation Service -- provides location data to apps.'
        'RetailDemo'         = 'Retail Demo Service -- for store display PCs only.'
        'wisvc'              = 'Windows Insider Service -- only needed for Insider builds.'
        'WMPNetworkSvc'      = 'Windows Media Player Network Sharing -- media streaming service.'
        'WerSvc'             = 'Windows Error Reporting -- sends crash data to Microsoft.'
        'XblAuthManager'     = 'Xbox Live Auth Manager -- Xbox gaming authentication.'
        'XblGameSave'        = 'Xbox Live Game Save -- Xbox cloud save sync.'
        'XboxNetApiSvc'      = 'Xbox Live Networking -- Xbox multiplayer networking.'
        'XboxGipSvc'         = 'Xbox Accessory Management -- Xbox controller support.'
    }

    $runningServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }
    $findings = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($svc in $runningServices) {
        if ($reviewCandidates.ContainsKey($svc.Name)) {
            $findings.Add([PSCustomObject]@{
                Name        = $svc.Name
                DisplayName = $svc.DisplayName
                Reason      = $reviewCandidates[$svc.Name]
                StartType   = (Get-Service $svc.Name | Select-Object -ExpandProperty StartType)
            })
        }
    }

    if ($findings.Count -eq 0) {
        Write-Log "No commonly unnecessary services are currently running." -Level SUCCESS
        return
    }

    Write-Log "Found $($findings.Count) service(s) that may warrant review:" -Level INFO
    Write-Host ""

    foreach ($finding in $findings) {
        Write-Host "    [?] " -ForegroundColor Yellow -NoNewline
        Write-Host "$($finding.DisplayName)" -ForegroundColor White -NoNewline
        Write-Host " ($($finding.Name))" -ForegroundColor DarkGray
        Write-Host "        $($finding.Reason)" -ForegroundColor Gray
        Write-Host "        Start Type: $($finding.StartType)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Log "RECOMMENDATION: Review these services with your IT team before changing." -Level DETAIL
    Write-Log "To disable a service: Set-Service -Name <name> -StartupType Disabled" -Level DETAIL

    Record-Action -Module 'ServiceAnalysis' -Action 'Analyze' -Target 'Services' `
                  -Result "Found $($findings.Count) review candidates"
}

function Invoke-BrowserCacheCleanup {
    <#
    .SYNOPSIS
        Cleans browser cache directories for major browsers.
    .DESCRIPTION
        Removes cached web data (images, scripts, stylesheets) from Chrome, Edge,
        Firefox, Opera, Brave, Vivaldi, and Waterfox. This data is automatically
        re-downloaded as you browse. Browsing history, bookmarks, and passwords
        are NOT touched.
    #>
    Write-SectionHeader -Title 'Browser Cache Cleanup' -Risk 'Low'

    Write-Log "WHY SAFE: Only cached web assets are removed (images, scripts, CSS)." -Level DETAIL
    Write-Log "NOT TOUCHED: History, bookmarks, passwords, cookies, extensions." -Level DETAIL
    Write-Log "IMPACT: Browsers will re-cache assets on next visit (minor speed impact initially)." -Level DETAIL

    $browsers = @(
        @{
            Name = 'Google Chrome'
            Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            Alt  = @(
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage"
            )
        }
        @{
            Name = 'Microsoft Edge'
            Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
            Alt  = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage"
            )
        }
        @{
            Name = 'Mozilla Firefox'
            Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
            IsFirefox = $true
        }
        @{
            Name = 'Opera'
            Path = "$env:APPDATA\Opera Software\Opera Stable\Cache"
            Alt  = @(
                "$env:APPDATA\Opera Software\Opera Stable\Code Cache"
                "$env:APPDATA\Opera Software\Opera Stable\Service Worker\CacheStorage"
            )
        }
        @{
            Name = 'Brave'
            Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache"
            Alt  = @(
                "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Code Cache"
                "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Service Worker\CacheStorage"
            )
        }
        @{
            Name = 'Vivaldi'
            Path = "$env:LOCALAPPDATA\Vivaldi\User Data\Default\Cache"
            Alt  = @(
                "$env:LOCALAPPDATA\Vivaldi\User Data\Default\Code Cache"
                "$env:LOCALAPPDATA\Vivaldi\User Data\Default\Service Worker\CacheStorage"
            )
        }
        @{
            Name = 'Waterfox'
            Path = "$env:LOCALAPPDATA\Waterfox\Profiles"
            IsFirefox = $true
        }
    )

    if (-not (Request-Confirmation "Clean browser cache files? (History, bookmarks, passwords are NOT affected.)")) {
        Write-Log "User declined browser cache cleanup." -Level SKIP
        return
    }

    foreach ($browser in $browsers) {
        Write-Log "Scanning $($browser.Name)..." -Level INFO

        if ($browser.ContainsKey('IsFirefox') -and $browser['IsFirefox']) {
            # Firefox has profile-based cache directories
            if (Test-Path $browser.Path) {
                $profiles = Get-ChildItem -Path $browser.Path -Directory -ErrorAction SilentlyContinue
                foreach ($profile in $profiles) {
                    $cachePath = Join-Path $profile.FullName 'cache2\entries'
                    if (Test-Path $cachePath) {
                        $result = Remove-SafeFiles -Path $cachePath -ModuleName 'BrowserCache' `
                                    -Description "Firefox cache ($($profile.Name))" -Recurse
                    }
                }
            } else {
                Write-Log "$($browser.Name) not found -- skipping." -Level SKIP
            }
            continue
        }

        # Chrome / Edge
        $altPaths = if ($browser.ContainsKey('Alt')) { $browser.Alt } else { @() }
        $allPaths = @($browser.Path) + @($altPaths | Where-Object { $_ })
        $found = $false

        foreach ($cachePath in $allPaths) {
            if (Test-Path $cachePath) {
                $found = $true
                $result = Remove-SafeFiles -Path $cachePath -ModuleName 'BrowserCache' `
                            -Description "$($browser.Name) web cache" -Recurse
            }
        }

        if (-not $found) {
            Write-Log "$($browser.Name) not found -- skipping." -Level SKIP
        }
    }

    Write-Log "Browser cache cleanup complete." -Level SUCCESS
}

function Invoke-EventLogCleanup {
    <#
    .SYNOPSIS
        Clears old Windows Event Logs that exceed size thresholds.
    .DESCRIPTION
        Archives and clears event logs that have grown large. Focuses on non-critical
        logs (Application, System logs are summarized but not cleared without approval).
        Requires administrator privileges.
    #>
    Write-SectionHeader -Title 'Event Log Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Event log cleanup requires administrator privileges." -Level WARNING
        Record-Action -Module 'EventLogs' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    Write-Log "WHY SAFE: Only clears non-security event logs. Logs can be exported first." -Level DETAIL
    Write-Log "IMPACT: Reduces disk usage from oversized log files." -Level DETAIL

    # Identify large event logs (>50 MB)
    $threshold = 50MB
    $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
            Where-Object { $_.FileSize -gt $threshold -and $_.LogName -notmatch 'Security' }

    if (-not $logs -or $logs.Count -eq 0) {
        Write-Log "No event logs exceed $(Format-FileSize $threshold). Nothing to clean." -Level SKIP
        return
    }

    Write-Log "Found $($logs.Count) log(s) exceeding $(Format-FileSize $threshold):" -Level INFO

    $totalLogSize = [long]0
    foreach ($log in $logs) {
        Write-Host "    - $($log.LogName): $(Format-FileSize $log.FileSize)" -ForegroundColor Gray
        $totalLogSize += $log.FileSize
    }

    if (-not (Request-Confirmation "Clear $($logs.Count) oversized event log(s) ($(Format-FileSize $totalLogSize))?")) {
        Write-Log "User declined event log cleanup." -Level SKIP
        return
    }

    foreach ($log in $logs) {
        if ($DryRun) {
            Write-Log "[DRY-RUN] Would clear: $($log.LogName) ($(Format-FileSize $log.FileSize))" -Level ACTION
            continue
        }

        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
            Write-Log "Cleared: $($log.LogName) (freed ~$(Format-FileSize $log.FileSize))" -Level SUCCESS
            Record-Action -Module 'EventLogs' -Action 'Clear' -Target $log.LogName `
                          -Result 'Completed' -BytesFreed $log.FileSize
        } catch {
            Write-Log "Failed to clear $($log.LogName): $($_.Exception.Message)" -Level ERROR
            $Script:TotalErrors++
        }
    }
}

# -----------------------------------------------------------------------------
# SECTION 4B -- ADVANCED CLEANUP MODULES
# -----------------------------------------------------------------------------

function Invoke-PrefetchCleanup {
    <#
    .SYNOPSIS
        Cleans the Windows Prefetch cache.
    .DESCRIPTION
        Prefetch files (.pf) are application launch traces used by Windows to speed up
        program loading. They are automatically regenerated and safe to remove. Clearing
        them may cause a brief slowdown on next launch of each application.
    #>
    Write-SectionHeader -Title 'Prefetch Cache Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Prefetch cleanup requires administrator privileges." -Level WARNING
        Record-Action -Module 'PrefetchCleanup' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    $prefetchPath = "$env:WINDIR\Prefetch"
    Write-Log "WHY SAFE: Prefetch files are auto-regenerated on next app launch." -Level DETAIL
    Write-Log "IMPACT: Brief first-launch slowdown per app; files rebuild automatically." -Level DETAIL

    $result = Remove-SafeFiles -Path $prefetchPath -ModuleName 'PrefetchCleanup' `
                -Description 'Windows application prefetch traces (.pf files)' -Recurse
}

function Invoke-DeliveryOptimizationCleanup {
    <#
    .SYNOPSIS
        Cleans the Windows Delivery Optimization cache.
    .DESCRIPTION
        Delivery Optimization (DO) caches Windows Update and Store app content to share
        with other PCs on the network or internet. Safe to clear -- Windows will
        re-download needed content on demand.
    #>
    Write-SectionHeader -Title 'Delivery Optimization Cache' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Delivery Optimization cleanup requires administrator." -Level WARNING
        Record-Action -Module 'DeliveryOptimization' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    Write-Log "WHY SAFE: Cached update/app content for peer sharing; re-downloaded on demand." -Level DETAIL
    Write-Log "IMPACT: Frees disk space; may slow next update download slightly." -Level DETAIL

    # Use the built-in cmdlet if available (Win10 1607+)
    $doPath = "$env:WINDIR\SoftwareDistribution\DeliveryOptimization"

    if ($DryRun) {
        $size = Get-FolderSize -Path $doPath -Recurse
        Write-Log "[DRY-RUN] Would clear Delivery Optimization cache ($(Format-FileSize $size))." -Level ACTION
        Record-Action -Module 'DeliveryOptimization' -Action 'WouldDelete' -Target $doPath -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Clear Delivery Optimization cache?")) {
        Write-Log "User declined." -Level SKIP
        return
    }

    # Try the clean cmdlet first, fall back to manual deletion
    try {
        if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
            Write-Log "Delivery Optimization cache cleared via cmdlet." -Level SUCCESS
            Record-Action -Module 'DeliveryOptimization' -Action 'Clear' -Target 'DO Cache' -Result 'Completed'
        } else {
            $result = Remove-SafeFiles -Path $doPath -ModuleName 'DeliveryOptimization' `
                        -Description 'Delivery Optimization peer cache' -Recurse
        }
    } catch {
        Write-Log "Error: $($_.Exception.Message)" -Level ERROR
        $Script:TotalErrors++
    }
}

function Invoke-WindowsOldCleanup {
    <#
    .SYNOPSIS
        Removes old Windows installation files (Windows.old).
    .DESCRIPTION
        After a major Windows update, the previous installation is retained in
        C:\Windows.old for rollback. These files can consume 10-30 GB. This module
        also checks for $Windows.~BT (upgrade staging). NOTE: Removing these files
        permanently prevents rollback to the previous Windows version.
    #>
    Write-SectionHeader -Title 'Old Windows Installation Cleanup' -Risk 'Medium'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Requires administrator privileges." -Level WARNING
        Record-Action -Module 'WindowsOldCleanup' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    Write-Log "WHY: Removes previous Windows version files after a major update." -Level DETAIL
    Write-Log "WARNING: You will NOT be able to roll back to the previous Windows version." -Level WARNING

    $targets = @(
        @{ Path = "$env:SystemDrive\Windows.old";    Desc = 'Previous Windows installation (rollback files)' }
        @{ Path = "$env:SystemDrive\`$Windows.~BT";  Desc = 'Windows upgrade staging directory' }
        @{ Path = "$env:SystemDrive\`$Windows.~WS";  Desc = 'Windows upgrade working directory' }
    )

    $totalSize = [long]0
    $foundAny = $false

    foreach ($target in $targets) {
        if (Test-Path $target.Path) {
            $size = Get-FolderSize -Path $target.Path -Recurse
            $totalSize += $size
            Write-Log "Found: $($target.Path) ($(Format-FileSize $size))" -Level INFO
            $foundAny = $true
        }
    }

    if (-not $foundAny) {
        Write-Log "No old Windows installation files found." -Level SKIP
        return
    }

    Write-Log "Total recoverable: $(Format-FileSize $totalSize)" -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would remove old Windows installation files ($(Format-FileSize $totalSize))." -Level ACTION
        Record-Action -Module 'WindowsOldCleanup' -Action 'WouldDelete' -Target 'Windows.old' `
                      -Result 'DryRun' -BytesFreed $totalSize
        return
    }

    if (-not (Request-Confirmation "Remove old Windows files ($(Format-FileSize $totalSize))? This prevents version rollback.")) {
        Write-Log "User declined." -Level SKIP
        return
    }

    foreach ($target in $targets) {
        if (Test-Path $target.Path) {
            try {
                # Take ownership and remove (required for Windows.old)
                $size = Get-FolderSize -Path $target.Path -Recurse
                & takeown /F $target.Path /R /A /D Y 2>$null | Out-Null
                & icacls $target.Path /grant Administrators:F /T /C /Q 2>$null | Out-Null
                Remove-Item -Path $target.Path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed: $($target.Path) ($(Format-FileSize $size))" -Level SUCCESS
                Record-Action -Module 'WindowsOldCleanup' -Action 'Delete' -Target $target.Path `
                              -Result 'Completed' -BytesFreed $size
            } catch {
                Write-Log "Error removing $($target.Path): $($_.Exception.Message)" -Level ERROR
                $Script:TotalErrors++
            }
        }
    }
}

function Invoke-CrashDumpCleanup {
    <#
    .SYNOPSIS
        Cleans Windows crash dump and minidump files.
    .DESCRIPTION
        Windows creates memory dump files when the system crashes (BSOD). These can be
        very large (full dumps = RAM size). Minidumps are small but accumulate. Safe to
        remove unless you are actively debugging a crash issue.
    #>
    Write-SectionHeader -Title 'Crash Dump Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Crash dump cleanup requires administrator." -Level WARNING
        Record-Action -Module 'CrashDumps' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    Write-Log "WHY SAFE: Crash dumps are diagnostic files; not needed unless debugging BSODs." -Level DETAIL
    Write-Log "IMPACT: Can recover significant space (full dumps = RAM size)." -Level DETAIL

    $targets = @(
        @{ Path = "$env:WINDIR\Minidump";       Desc = 'Small crash minidump files' }
        @{ Path = "$env:WINDIR\MEMORY.DMP";      Desc = 'Full system memory dump' }
        @{ Path = "$env:WINDIR\LiveKernelReports"; Desc = 'Live kernel diagnostic reports' }
        @{ Path = "$env:LOCALAPPDATA\CrashDumps"; Desc = 'Application crash dump files' }
    )

    foreach ($target in $targets) {
        if ($target.Path -match '\.DMP$') {
            # Single file
            if (Test-Path $target.Path) {
                $size = (Get-Item $target.Path -Force).Length
                Write-Log "Found: $($target.Path) ($(Format-FileSize $size))" -Level INFO
                if ($DryRun) {
                    Write-Log "[DRY-RUN] Would delete $(Format-FileSize $size) dump file." -Level ACTION
                    Record-Action -Module 'CrashDumps' -Action 'WouldDelete' -Target $target.Path `
                                  -Result 'DryRun' -BytesFreed $size
                } else {
                    try {
                        Remove-Item $target.Path -Force -ErrorAction Stop
                        Write-Log "Deleted: $($target.Path)" -Level SUCCESS
                        Record-Action -Module 'CrashDumps' -Action 'Delete' -Target $target.Path `
                                      -Result 'Completed' -BytesFreed $size
                    } catch {
                        Write-Log "Could not delete (may be in use): $($_.Exception.Message)" -Level WARNING
                    }
                }
            }
        } else {
            $result = Remove-SafeFiles -Path $target.Path -ModuleName 'CrashDumps' `
                        -Description $target.Desc -Recurse
        }
    }
}

function Invoke-InstallerCleanup {
    <#
    .SYNOPSIS
        Cleans the Windows Installer patch cache.
    .DESCRIPTION
        The Windows Installer cache ($PatchCache$) stores MSI/MSP patch files used for
        repair and uninstall operations. Orphaned entries can consume significant space.
        Only the $PatchCache$ subfolder is targeted -- the main Installer folder is
        left intact to avoid breaking uninstall capability.
    #>
    Write-SectionHeader -Title 'Installer Patch Cache Cleanup' -Risk 'Medium'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Requires administrator privileges." -Level WARNING
        Record-Action -Module 'InstallerCleanup' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    $patchCache = "$env:WINDIR\Installer\`$PatchCache`$"

    Write-Log "WHY SAFE: Only targets the PatchCache subfolder, not the main Installer DB." -Level DETAIL
    Write-Log "WARNING: May affect ability to repair very old installations." -Level WARNING
    Write-Log "IMPACT: Can recover 500 MB - 10 GB on older systems." -Level DETAIL

    if (-not (Test-Path $patchCache)) {
        Write-Log "No installer patch cache found." -Level SKIP
        return
    }

    $result = Remove-SafeFiles -Path $patchCache -ModuleName 'InstallerCleanup' `
                -Description 'Windows Installer orphaned patch cache files' -Recurse
}

function Invoke-ShaderCacheCleanup {
    <#
    .SYNOPSIS
        Cleans GPU shader caches for NVIDIA, AMD, and DirectX.
    .DESCRIPTION
        GPU drivers maintain compiled shader caches to speed up game and application
        rendering. These caches are fully regenerated automatically. Clearing them can
        fix graphical glitches and recover significant space (500 MB - 10 GB on gaming
        systems).
    #>
    Write-SectionHeader -Title 'GPU Shader Cache Cleanup' -Risk 'Low'

    Write-Log "WHY SAFE: Shader caches are auto-rebuilt by the GPU driver on next use." -Level DETAIL
    Write-Log "IMPACT: Brief stuttering in games/apps on first run as shaders recompile." -Level DETAIL

    $targets = @(
        @{ Path = "$env:LOCALAPPDATA\NVIDIA\DXCache";           Desc = 'NVIDIA DirectX shader cache' }
        @{ Path = "$env:LOCALAPPDATA\NVIDIA\GLCache";           Desc = 'NVIDIA OpenGL shader cache' }
        @{ Path = "$env:LOCALAPPDATA\AMD\DxCache";              Desc = 'AMD DirectX shader cache' }
        @{ Path = "$env:LOCALAPPDATA\AMD\GLCache";              Desc = 'AMD OpenGL shader cache' }
        @{ Path = "$env:LOCALAPPDATA\D3DSCache";                Desc = 'DirectX shader cache' }
        @{ Path = "$env:LOCALAPPDATA\Intel\ShaderCache";        Desc = 'Intel GPU shader cache' }
        @{ Path = "$env:LOCALAPPDATA\UnrealEngine\Common\DxPipelineCache"; Desc = 'Unreal Engine pipeline cache' }
        @{ Path = "$env:TEMP\NVIDIA Corporation\NV_Cache";      Desc = 'NVIDIA temporary shader cache' }
    )

    if (-not (Request-Confirmation "Clean GPU shader caches? (Brief shader recompilation on next use.)")) {
        Write-Log "User declined shader cache cleanup." -Level SKIP
        return
    }

    $foundAny = $false
    foreach ($target in $targets) {
        if (Test-Path $target.Path) {
            $foundAny = $true
            $result = Remove-SafeFiles -Path $target.Path -ModuleName 'ShaderCache' `
                        -Description $target.Desc -Recurse
        }
    }

    if (-not $foundAny) {
        Write-Log "No GPU shader caches found (no NVIDIA/AMD/Intel GPU detected)." -Level SKIP
    }

    Write-Log "Shader cache cleanup complete." -Level SUCCESS
}

function Invoke-ThumbCacheCleanup {
    <#
    .SYNOPSIS
        Cleans Windows thumbnail cache database files.
    .DESCRIPTION
        Windows generates thumbnail databases (thumbcache_*.db) in the Explorer cache
        folder for file/folder preview icons. These are auto-regenerated when browsing
        folders. Clearing fixes corrupted thumbnails and recovers space.
    #>
    Write-SectionHeader -Title 'Thumbnail Cache Cleanup' -Risk 'Low'

    Write-Log "WHY SAFE: Thumbnail databases are auto-regenerated when browsing folders." -Level DETAIL
    Write-Log "IMPACT: Thumbnails will rebuild on next folder visit (brief delay)." -Level DETAIL

    $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"

    if (-not (Test-Path $thumbPath)) {
        Write-Log "Thumbnail cache path not found." -Level SKIP
        return
    }

    # Target only thumbcache and iconcache files
    $thumbFiles = Get-ChildItem -Path $thumbPath -File -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '^(thumbcache_|iconcache_).*\.db$' }

    if (-not $thumbFiles -or $thumbFiles.Count -eq 0) {
        Write-Log "No thumbnail cache files found." -Level SKIP
        return
    }

    $totalSize = ($thumbFiles | Measure-Object -Property Length -Sum).Sum
    Write-Log "Found $($thumbFiles.Count) cache files ($(Format-FileSize $totalSize))." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $($thumbFiles.Count) thumbnail cache files." -Level ACTION
        Record-Action -Module 'ThumbCacheCleanup' -Action 'WouldDelete' -Target $thumbPath `
                      -Result 'DryRun' -BytesFreed $totalSize -FilesAffected $thumbFiles.Count
        return
    }

    $freed = [long]0; $removed = 0
    foreach ($file in $thumbFiles) {
        try {
            $size = $file.Length
            Remove-Item $file.FullName -Force -ErrorAction Stop
            $freed += $size; $removed++
        } catch {
            Write-Log "Skipped (in use): $($file.Name)" -Level DETAIL -NoConsole
        }
    }

    Write-Log "Deleted $removed/$($thumbFiles.Count) thumbnail files, freed $(Format-FileSize $freed)." -Level SUCCESS
    Record-Action -Module 'ThumbCacheCleanup' -Action 'Delete' -Target $thumbPath `
                  -Result 'Completed' -BytesFreed $freed -FilesAffected $removed
}

function Invoke-ComponentStoreCleanup {
    <#
    .SYNOPSIS
        Cleans the Windows Component Store (WinSxS) using DISM.
    .DESCRIPTION
        The WinSxS folder stores all Windows component versions for servicing and
        rollback. Over time it grows significantly. DISM /StartComponentCleanup safely
        removes superseded components. This is Microsoft's official method and is fully
        safe. May take 10-30 minutes.
    #>
    Write-SectionHeader -Title 'Component Store (WinSxS) Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: DISM component cleanup requires administrator." -Level WARNING
        Record-Action -Module 'ComponentStoreCleanup' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    Write-Log "WHY SAFE: Uses Microsoft's official DISM tool to remove superseded components." -Level DETAIL
    Write-Log "IMPACT: Can recover 1-15 GB; takes 10-30 minutes to complete." -Level DETAIL
    Write-Log "NOTE: Never manually delete from WinSxS -- always use DISM." -Level WARNING

    # Check component store size first
    try {
        Write-Log "Analyzing component store..." -Level INFO
        $dismAnalysis = & dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
        $dismOutput = $dismAnalysis -join "`n"

        if ($dismOutput -match 'Component Store Cleanup Recommended\s*:\s*Yes') {
            Write-Log "DISM recommends cleanup." -Level INFO
        } elseif ($dismOutput -match 'Component Store Cleanup Recommended\s*:\s*No') {
            Write-Log "DISM reports cleanup is not needed at this time." -Level SKIP
            Record-Action -Module 'ComponentStoreCleanup' -Action 'Analyze' -Target 'WinSxS' -Result 'NotNeeded'
            return
        }

        # Extract size info
        if ($dismOutput -match 'Size of Component Store\s*:\s*(.+)') {
            Write-Log "Current WinSxS size: $($Matches[1].Trim())" -Level INFO
        }
    } catch {
        Write-Log "Could not analyze component store: $($_.Exception.Message)" -Level WARNING
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would run DISM /StartComponentCleanup." -Level ACTION
        Record-Action -Module 'ComponentStoreCleanup' -Action 'WouldRun' -Target 'DISM' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Run DISM component cleanup? This may take 10-30 minutes.")) {
        Write-Log "User declined." -Level SKIP
        return
    }

    Write-Log "Running DISM /StartComponentCleanup (this will take a while)..." -Level ACTION
    try {
        $process = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup' `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($process.ExitCode -eq 0) {
            Write-Log "DISM component cleanup completed successfully." -Level SUCCESS
            Record-Action -Module 'ComponentStoreCleanup' -Action 'Cleanup' -Target 'WinSxS' -Result 'Completed'
        } else {
            Write-Log "DISM exited with code $($process.ExitCode)." -Level WARNING
        }
    } catch {
        Write-Log "DISM error: $($_.Exception.Message)" -Level ERROR
        $Script:TotalErrors++
    }
}

function Invoke-DNSCacheFlush {
    <#
    .SYNOPSIS
        Flushes the DNS resolver cache.
    .DESCRIPTION
        Clears all cached DNS lookups. This resolves stale DNS entries that can cause
        connectivity issues. The cache rebuilds automatically as you browse.
    #>
    Write-SectionHeader -Title 'DNS Cache Flush' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: DNS flush requires administrator privileges." -Level WARNING
        Record-Action -Module 'DNSCacheFlush' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    Write-Log "WHY SAFE: DNS cache auto-rebuilds as you browse the internet." -Level DETAIL
    Write-Log "IMPACT: Resolves stale DNS entries; brief lookup delay on first visits." -Level DETAIL

    # Show current cache stats
    try {
        $stats = Get-DnsClientCache -ErrorAction SilentlyContinue
        $entryCount = ($stats | Measure-Object).Count
        Write-Log "Current DNS cache: $entryCount entries." -Level INFO
    } catch {
        $entryCount = 0
        Write-Log "Could not read DNS cache stats." -Level DETAIL
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would flush DNS resolver cache ($entryCount entries)." -Level ACTION
        Record-Action -Module 'DNSCacheFlush' -Action 'WouldFlush' -Target 'DNS' -Result 'DryRun'
        return
    }

    try {
        Clear-DnsClientCache -ErrorAction Stop
        Write-Log "DNS cache flushed successfully ($entryCount entries cleared)." -Level SUCCESS
        Record-Action -Module 'DNSCacheFlush' -Action 'Flush' -Target 'DNS Cache' `
                      -Result 'Completed' -FilesAffected $entryCount
    } catch {
        Write-Log "Error flushing DNS: $($_.Exception.Message)" -Level ERROR
        $Script:TotalErrors++
    }
}

function Invoke-WindowsStoreCacheCleanup {
    <#
    .SYNOPSIS
        Resets the Windows Store cache.
    .DESCRIPTION
        Clears the Microsoft Store app cache using wsreset.exe. Fixes Store download
        issues, stuck updates, and corrupted cache. Does NOT remove installed apps,
        purchases, or account data.
    #>
    Write-SectionHeader -Title 'Windows Store Cache Reset' -Risk 'Low'

    Write-Log "WHY SAFE: Only clears Store download cache; apps and purchases are unaffected." -Level DETAIL
    Write-Log "IMPACT: Fixes Store connectivity and download issues." -Level DETAIL

    # Also clean the local Store cache files
    $storeCachePaths = @()
    $packagesPath = "$env:LOCALAPPDATA\Packages"
    if (Test-Path $packagesPath) {
        $storeDirs = Get-ChildItem $packagesPath -Directory -Filter 'Microsoft.WindowsStore_*' -ErrorAction SilentlyContinue
        foreach ($dir in $storeDirs) {
            $lc = Join-Path $dir.FullName 'LocalCache'
            if (Test-Path $lc) { $storeCachePaths += $lc }
        }
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would run wsreset.exe to clear Store cache." -Level ACTION
        if ($storeCachePaths) {
            $cacheSize = [long]0
            foreach ($p in $storeCachePaths) { $cacheSize += (Get-FolderSize -Path $p -Recurse) }
            Write-Log "[DRY-RUN] Would also clear $(Format-FileSize $cacheSize) of Store cache files." -Level ACTION
        }
        Record-Action -Module 'WindowsStoreCache' -Action 'WouldReset' -Target 'Store Cache' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Reset Windows Store cache?")) {
        Write-Log "User declined." -Level SKIP
        return
    }

    try {
        Write-Log "Running wsreset.exe..." -Level ACTION
        $proc = Start-Process -FilePath 'wsreset.exe' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-Log "Store cache reset completed." -Level SUCCESS
        Record-Action -Module 'WindowsStoreCache' -Action 'Reset' -Target 'Store Cache' -Result 'Completed'
    } catch {
        Write-Log "Error resetting Store cache: $($_.Exception.Message)" -Level ERROR
        $Script:TotalErrors++
    }

    # Clean local cache files
    foreach ($p in $storeCachePaths) {
        $result = Remove-SafeFiles -Path $p -ModuleName 'WindowsStoreCache' `
                    -Description 'Microsoft Store local cache files' -Recurse
    }
}

function Invoke-SystemHealthCheck {
    <#
    .SYNOPSIS
        Generates a comprehensive system health report (READ-ONLY).
    .DESCRIPTION
        Analyzes disk health, memory usage, system uptime, reliability events, and
        overall system state. Provides actionable recommendations. Does NOT modify
        any system settings.
    #>
    Write-SectionHeader -Title 'System Health Report' -Risk 'None (read-only)'

    Write-Log "This module is READ-ONLY. No changes will be made." -Level INFO

    # ── Disk Health ──
    Write-Host ""
    Write-Host "    DISK HEALTH" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    foreach ($drive in $drives) {
        $usedPct = [math]::Round((($drive.Size - $drive.FreeSpace) / $drive.Size) * 100, 1)
        $freeText = Format-FileSize $drive.FreeSpace
        $totalText = Format-FileSize $drive.Size
        $barWidth = 30
        $filledWidth = [math]::Round(($usedPct / 100) * $barWidth)
        $emptyWidth = $barWidth - $filledWidth
        $bar = ('#' * $filledWidth) + ('-' * $emptyWidth)
        $barColor = if ($usedPct -ge 90) { 'Red' } elseif ($usedPct -ge 75) { 'Yellow' } else { 'Green' }

        Write-Host "    $($drive.DeviceID) " -ForegroundColor White -NoNewline
        Write-Host "[$bar] " -ForegroundColor $barColor -NoNewline
        Write-Host "$usedPct% used" -ForegroundColor $barColor -NoNewline
        Write-Host "  ($freeText free of $totalText)" -ForegroundColor DarkGray

        if ($usedPct -ge 90) {
            Write-Host "       >> CRITICAL: Disk nearly full! Immediate cleanup recommended." -ForegroundColor Red
        } elseif ($usedPct -ge 75) {
            Write-Host "       >> WARNING: Disk usage high. Consider running cleanup." -ForegroundColor Yellow
        }
    }

    # ── Memory ──
    Write-Host ""
    Write-Host "    MEMORY" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedRAM = $totalRAM - $freeRAM
        $ramPct = [math]::Round(($usedRAM / $totalRAM) * 100, 1)

        Write-Host "    Total: ${totalRAM} GB | Used: ${usedRAM} GB ($ramPct%) | Free: ${freeRAM} GB" -ForegroundColor Gray

        if ($ramPct -ge 90) {
            Write-Host "       >> HIGH MEMORY PRESSURE: Consider closing unused applications." -ForegroundColor Yellow
        }
    }

    # ── System Uptime ──
    Write-Host ""
    Write-Host "    SYSTEM UPTIME" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    if ($os) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeText = "$($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
        Write-Host "    Last boot: $($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
        Write-Host "    Uptime:    $uptimeText" -ForegroundColor $(if ($uptime.Days -ge 14) { 'Yellow' } else { 'Gray' })

        if ($uptime.Days -ge 14) {
            Write-Host "       >> RECOMMENDATION: Consider rebooting. Uptime > 14 days." -ForegroundColor Yellow
        }
    }

    # ── Windows Version ──
    Write-Host ""
    Write-Host "    WINDOWS VERSION" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    try {
        $winVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $build = "$($winVer.CurrentMajorVersionNumber).$($winVer.CurrentMinorVersionNumber).$($winVer.CurrentBuildNumber).$($winVer.UBR)"
        $displayVer = $winVer.DisplayVersion
        Write-Host "    Edition: $($winVer.ProductName)" -ForegroundColor Gray
        Write-Host "    Version: $displayVer (Build $build)" -ForegroundColor Gray
    } catch {
        Write-Host "    Could not read version info." -ForegroundColor DarkGray
    }

    # ── Recent Errors ──
    Write-Host ""
    Write-Host "    RECENT SYSTEM ERRORS (Last 7 Days)" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    try {
        $weekAgo = (Get-Date).AddDays(-7)
        $errors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=$weekAgo} -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($errors) {
            foreach ($err in $errors) {
                Write-Host "    [$($err.TimeCreated.ToString('MM-dd HH:mm'))] " -ForegroundColor Red -NoNewline
                Write-Host "$($err.ProviderName): $($err.Message.Substring(0, [math]::Min(80, $err.Message.Length)))..." -ForegroundColor Gray
            }
        } else {
            Write-Host "    No critical errors in the past 7 days." -ForegroundColor Green
        }
    } catch {
        Write-Host "    Could not read event logs." -ForegroundColor DarkGray
    }

    # ── Top Memory Consumers ──
    Write-Host ""
    Write-Host "    TOP MEMORY CONSUMERS" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    try {
        $topProcs = Get-Process -ErrorAction SilentlyContinue |
                    Sort-Object WorkingSet64 -Descending |
                    Select-Object -First 5
        foreach ($proc in $topProcs) {
            $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
            Write-Host "    $(($proc.ProcessName).PadRight(30)) " -ForegroundColor Gray -NoNewline
            Write-Host "$($memMB.ToString().PadLeft(6)) MB" -ForegroundColor $(if ($memMB -ge 1000) { 'Yellow' } else { 'Gray' })
        }
    } catch {}

    Write-Host ""
    Record-Action -Module 'SystemHealthCheck' -Action 'Analyze' -Target 'System Health' -Result 'Completed'
}

function Invoke-NetworkAnalysis {
    <#
    .SYNOPSIS
        Network diagnostics and configuration report (READ-ONLY).
    .DESCRIPTION
        Displays network adapter configuration, DNS settings, active connections,
        and basic connectivity test results. No changes are made.
    #>
    Write-SectionHeader -Title 'Network Diagnostics' -Risk 'None (read-only)'

    Write-Log "This module is READ-ONLY. No changes will be made." -Level INFO

    # ── Active Adapters ──
    Write-Host ""
    Write-Host "    NETWORK ADAPTERS" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($adapter in $adapters) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $ip = if ($ipConfig) { $ipConfig.IPAddress } else { 'N/A' }

            Write-Host "    $($adapter.Name)" -ForegroundColor White
            Write-Host "      Status: " -ForegroundColor DarkGray -NoNewline
            Write-Host "Up" -ForegroundColor Green -NoNewline
            Write-Host "  |  Speed: $($adapter.LinkSpeed)  |  IP: $ip" -ForegroundColor Gray
        }
    } catch {
        Write-Host "    Could not enumerate adapters." -ForegroundColor DarkGray
    }

    # ── DNS Configuration ──
    Write-Host ""
    Write-Host "    DNS CONFIGURATION" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                      Where-Object { $_.ServerAddresses }
        $seenDns = @{}
        foreach ($dns in $dnsServers) {
            $key = $dns.ServerAddresses -join ','
            if (-not $seenDns.ContainsKey($key)) {
                $seenDns[$key] = $true
                $adapterName = (Get-NetAdapter -InterfaceIndex $dns.InterfaceIndex -ErrorAction SilentlyContinue).Name
                Write-Host "    $adapterName : $($dns.ServerAddresses -join ', ')" -ForegroundColor Gray
            }
        }

        # DNS cache stats
        $cacheEntries = (Get-DnsClientCache -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host "    DNS Cache: $cacheEntries entries" -ForegroundColor Gray
    } catch {
        Write-Host "    Could not read DNS configuration." -ForegroundColor DarkGray
    }

    # ── Connectivity Test ──
    Write-Host ""
    Write-Host "    CONNECTIVITY" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    $testTargets = @(
        @{ Name = 'Internet (DNS)';    Host = '8.8.8.8' }
        @{ Name = 'Microsoft';         Host = 'www.microsoft.com' }
    )

    foreach ($target in $testTargets) {
        try {
            $ping = Test-Connection -ComputerName $target.Host -Count 1 -Quiet -ErrorAction SilentlyContinue
            $status = if ($ping) { 'OK' } else { 'FAIL' }
            $color = if ($ping) { 'Green' } else { 'Red' }
            Write-Host "    $($target.Name.PadRight(25))" -ForegroundColor Gray -NoNewline
            Write-Host $status -ForegroundColor $color
        } catch {
            Write-Host "    $($target.Name.PadRight(25))" -ForegroundColor Gray -NoNewline
            Write-Host "ERROR" -ForegroundColor Red
        }
    }

    # ── Active Connections Summary ──
    Write-Host ""
    Write-Host "    ACTIVE CONNECTIONS SUMMARY" -ForegroundColor White
    Write-Host "    $([string]::new('-', 60))" -ForegroundColor DarkGray

    try {
        $connections = Get-NetTCPConnection -ErrorAction SilentlyContinue |
                       Group-Object State | Sort-Object Count -Descending
        foreach ($group in $connections) {
            Write-Host "    $($group.Name.PadRight(20)) $($group.Count) connections" -ForegroundColor Gray
        }
    } catch {
        Write-Host "    Could not read connection data." -ForegroundColor DarkGray
    }

    Write-Host ""
    Record-Action -Module 'NetworkAnalysis' -Action 'Analyze' -Target 'Network' -Result 'Completed'
}

# ── NEW MODULES: Error Reporting, Logs, Defender, Search, Shadow Copies, Dev Tools, App Caches, Font, .NET, Analysis ──

function Invoke-ErrorReportingCleanup {
    Write-SectionHeader -Title 'Windows Error Reporting Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log -Message 'SKIPPED: Requires administrator privileges.' -Level WARNING
        return
    }

    Write-Log -Message 'WHY SAFE: Error reports are diagnostic data already sent (or queued). No system impact.' -Level DETAIL
    Write-Log -Message 'IMPACT: Removes old crash/hang reports from WER queue and archive.' -Level DETAIL

    $werPaths = @(
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
        "$env:ProgramData\Microsoft\Windows\WER\Temp"
    )

    $totalBytes = [long]0; $totalFiles = 0
    foreach ($p in $werPaths) {
        if (Test-Path $p) {
            $r = Get-ScanResult -Path $p -Recurse
            if ($r.Files -gt 0) {
                Write-Log -Message "Found $($r.Files) files ($(Format-FileSize $r.Bytes)) in $(Split-Path $p -Leaf)" -Level INFO
                $totalBytes += $r.Bytes; $totalFiles += $r.Files
            }
        }
    }

    if ($totalFiles -eq 0) {
        Write-Log -Message 'No error reports to clean.' -Level SUCCESS
        return
    }

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would delete $totalFiles error report files ($(Format-FileSize $totalBytes))" -Level ACTION
        Record-Action -Module 'ErrorReporting' -Action 'WouldDelete' -Target 'WER Reports' -Result 'DryRun' -BytesFreed $totalBytes -FilesAffected $totalFiles
    } else {
        $confirmed = Get-UserConfirmation -Message "Delete $totalFiles error report files ($(Format-FileSize $totalBytes))?"
        if ($confirmed) {
            foreach ($p in $werPaths) {
                if (Test-Path $p) {
                    Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $Script:TotalBytesFreed += $totalBytes
            $Script:TotalFilesRemoved += $totalFiles
            Write-Log -Message "Removed $totalFiles error reports ($(Format-FileSize $totalBytes))" -Level SUCCESS
            Record-Action -Module 'ErrorReporting' -Action 'Delete' -Target 'WER Reports' -Result 'Completed' -BytesFreed $totalBytes -FilesAffected $totalFiles
        }
    }
}

function Invoke-WindowsLogFileCleanup {
    Write-SectionHeader -Title 'Diagnostic Log Archive Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log -Message 'SKIPPED: Requires administrator privileges.' -Level WARNING
        return
    }

    Write-Log -Message 'WHY SAFE: Only removes old rotated log files (>30 days). Active logs are untouched.' -Level DETAIL
    Write-Log -Message 'IMPACT: Clears CBS, DISM, and system diagnostic archives.' -Level DETAIL

    $logDirs = @(
        @{ Path = "$env:WINDIR\Logs\CBS";        Name = 'CBS (Component Based Servicing)' },
        @{ Path = "$env:WINDIR\Logs\DISM";       Name = 'DISM Logs' },
        @{ Path = "$env:WINDIR\Logs\WindowsUpdate"; Name = 'Windows Update ETL Logs' },
        @{ Path = "$env:WINDIR\System32\LogFiles\Srt"; Name = 'Startup Repair Logs' },
        @{ Path = "$env:WINDIR\Panther";         Name = 'Setup Panther Logs' }
    )

    $totalBytes = [long]0; $totalFiles = 0
    $cutoff = (Get-Date).AddDays(-30)

    foreach ($dir in $logDirs) {
        if (Test-Path $dir.Path) {
            try {
                $oldFiles = Get-ChildItem $dir.Path -File -Recurse -ErrorAction SilentlyContinue |
                            Where-Object { $_.LastWriteTime -lt $cutoff }
                if ($oldFiles) {
                    $dirBytes = ($oldFiles | Measure-Object -Property Length -Sum).Sum
                    $dirCount = $oldFiles.Count
                    Write-Log -Message "Found $dirCount old files ($(Format-FileSize $dirBytes)) in $($dir.Name)" -Level INFO
                    $totalBytes += $dirBytes; $totalFiles += $dirCount
                }
            } catch {}
        }
    }

    # Also check CBS.log itself (can grow to 1-2 GB)
    $cbsLog = "$env:WINDIR\Logs\CBS\CBS.log"
    if (Test-Path $cbsLog) {
        $cbsSize = (Get-Item $cbsLog -ErrorAction SilentlyContinue).Length
        if ($cbsSize -gt 50MB) {
            Write-Log -Message "CBS.log is $(Format-FileSize $cbsSize) (oversized, will be rotated)" -Level INFO
        }
    }

    if ($totalFiles -eq 0) {
        Write-Log -Message 'No old diagnostic logs to clean.' -Level SUCCESS
        return
    }

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would delete $totalFiles old log files ($(Format-FileSize $totalBytes))" -Level ACTION
        Record-Action -Module 'WindowsLogFiles' -Action 'WouldDelete' -Target 'Diagnostic Logs' -Result 'DryRun' -BytesFreed $totalBytes -FilesAffected $totalFiles
    } else {
        $confirmed = Get-UserConfirmation -Message "Delete $totalFiles old diagnostic log files ($(Format-FileSize $totalBytes))?"
        if ($confirmed) {
            foreach ($dir in $logDirs) {
                if (Test-Path $dir.Path) {
                    Get-ChildItem $dir.Path -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt $cutoff } |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                }
            }
            $Script:TotalBytesFreed += $totalBytes
            $Script:TotalFilesRemoved += $totalFiles
            Write-Log -Message "Removed $totalFiles old log files ($(Format-FileSize $totalBytes))" -Level SUCCESS
            Record-Action -Module 'WindowsLogFiles' -Action 'Delete' -Target 'Diagnostic Logs' -Result 'Completed' -BytesFreed $totalBytes -FilesAffected $totalFiles
        }
    }
}

function Invoke-DefenderCacheCleanup {
    Write-SectionHeader -Title 'Windows Defender History Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log -Message 'SKIPPED: Requires administrator privileges.' -Level WARNING
        return
    }

    Write-Log -Message 'WHY SAFE: Only removes scan history and old definition backups. Active definitions untouched.' -Level DETAIL
    Write-Log -Message 'IMPACT: Clears old scan results. Definitions auto-update on next scan cycle.' -Level DETAIL

    $defenderPaths = @(
        @{ Path = "$env:ProgramData\Microsoft\Windows Defender\Scans\History"; Name = 'Scan History' },
        @{ Path = "$env:ProgramData\Microsoft\Windows Defender\Scans\MetaStore"; Name = 'Scan MetaStore' },
        @{ Path = "$env:ProgramData\Microsoft\Windows Defender\LocalCopy"; Name = 'Definition Backups' }
    )

    $totalBytes = [long]0; $totalFiles = 0
    foreach ($d in $defenderPaths) {
        if (Test-Path $d.Path) {
            $r = Get-ScanResult -Path $d.Path -Recurse
            if ($r.Files -gt 0) {
                Write-Log -Message "Found $($r.Files) files ($(Format-FileSize $r.Bytes)) in $($d.Name)" -Level INFO
                $totalBytes += $r.Bytes; $totalFiles += $r.Files
            }
        }
    }

    if ($totalFiles -eq 0) {
        Write-Log -Message 'Defender cache is clean.' -Level SUCCESS
        return
    }

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would delete $totalFiles Defender history files ($(Format-FileSize $totalBytes))" -Level ACTION
        Record-Action -Module 'DefenderCache' -Action 'WouldDelete' -Target 'Defender History' -Result 'DryRun' -BytesFreed $totalBytes -FilesAffected $totalFiles
    } else {
        $confirmed = Get-UserConfirmation -Message "Delete $totalFiles Defender history files ($(Format-FileSize $totalBytes))?"
        if ($confirmed) {
            foreach ($d in $defenderPaths) {
                if (Test-Path $d.Path) {
                    Get-ChildItem $d.Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $Script:TotalBytesFreed += $totalBytes
            $Script:TotalFilesRemoved += $totalFiles
            Write-Log -Message "Removed $totalFiles Defender history files ($(Format-FileSize $totalBytes))" -Level SUCCESS
            Record-Action -Module 'DefenderCache' -Action 'Delete' -Target 'Defender History' -Result 'Completed' -BytesFreed $totalBytes -FilesAffected $totalFiles
        }
    }
}

function Invoke-SearchIndexCleanup {
    Write-SectionHeader -Title 'Windows Search Index Cleanup' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log -Message 'SKIPPED: Requires administrator privileges.' -Level WARNING
        return
    }

    Write-Log -Message 'WHY SAFE: Windows Search auto-rebuilds the index on next use.' -Level DETAIL
    Write-Log -Message 'IMPACT: Search results may be slow until re-indexing completes (minutes to hours).' -Level DETAIL

    $searchPath = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
    if (-not (Test-Path $searchPath)) {
        Write-Log -Message 'Search index path not found.' -Level SKIP
        return
    }

    $r = Get-ScanResult -Path $searchPath -Recurse
    Write-Log -Message "Search index size: $(Format-FileSize $r.Bytes) ($($r.Files) files)" -Level INFO

    if ($r.Bytes -lt 10MB) {
        Write-Log -Message 'Search index is small -- no cleanup needed.' -Level SUCCESS
        return
    }

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would stop WSearch service and rebuild index ($(Format-FileSize $r.Bytes))" -Level ACTION
        Record-Action -Module 'SearchIndexCleanup' -Action 'WouldRebuild' -Target 'Search Index' -Result 'DryRun' -BytesFreed $r.Bytes
    } else {
        $confirmed = Get-UserConfirmation -Message "Rebuild search index? Current size: $(Format-FileSize $r.Bytes). Search will be slow until re-indexed."
        if ($confirmed) {
            try {
                Stop-Service WSearch -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Get-ChildItem $searchPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Start-Service WSearch -ErrorAction SilentlyContinue
                $Script:TotalBytesFreed += $r.Bytes
                Write-Log -Message "Search index cleared ($(Format-FileSize $r.Bytes)). Re-indexing will begin automatically." -Level SUCCESS
                Record-Action -Module 'SearchIndexCleanup' -Action 'Rebuild' -Target 'Search Index' -Result 'Completed' -BytesFreed $r.Bytes
            } catch {
                Write-Log -Message "Failed to rebuild search index: $($_.Exception.Message)" -Level ERROR
                Start-Service WSearch -ErrorAction SilentlyContinue
            }
        }
    }
}

function Invoke-ShadowCopyCleanup {
    Write-SectionHeader -Title 'Volume Shadow Copy Cleanup' -Risk 'Medium'

    if (-not $Script:IsAdmin) {
        Write-Log -Message 'SKIPPED: Requires administrator privileges.' -Level WARNING
        return
    }

    Write-Log -Message 'WHY: Shadow copies store snapshots for System Restore. Old copies consume significant space.' -Level DETAIL
    Write-Log -Message 'IMPACT: Removes old restore points. Latest restore point is PRESERVED.' -Level DETAIL
    Write-Log -Message 'RISK: You will lose the ability to restore to older restore points.' -Level WARNING

    try {
        $shadows = Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue
        if (-not $shadows -or $shadows.Count -eq 0) {
            Write-Log -Message 'No shadow copies found.' -Level SUCCESS
            return
        }

        $totalBytes = [long]0
        foreach ($s in $shadows) {
            try { $totalBytes += [long]$s.MaxSpace } catch {}
        }

        Write-Log -Message "Found $($shadows.Count) shadow copies." -Level INFO
        Write-Log -Message "Estimated storage usage (may share blocks): $(Format-FileSize $totalBytes)" -Level INFO

        if ($DryRun) {
            Write-Log -Message "[DRY-RUN] Would delete $($shadows.Count - 1) older shadow copies (keeping newest)." -Level ACTION
            Record-Action -Module 'ShadowCopyCleanup' -Action 'WouldDelete' -Target 'Shadow Copies' -Result 'DryRun' -FilesAffected ($shadows.Count - 1)
        } else {
            if ($shadows.Count -le 1) {
                Write-Log -Message 'Only 1 shadow copy exists -- keeping it.' -Level INFO
                return
            }
            $confirmed = Get-UserConfirmation -Message "Delete $($shadows.Count - 1) old shadow copies (keeping newest)?"
            if ($confirmed) {
                # Delete all except the most recent
                $sorted = $shadows | Sort-Object InstallDate -Descending
                $toDelete = $sorted | Select-Object -Skip 1
                $deleted = 0
                foreach ($s in $toDelete) {
                    try {
                        $s | Remove-CimInstance -ErrorAction Stop
                        $deleted++
                    } catch {
                        Write-Log -Message "Could not delete shadow copy: $($_.Exception.Message)" -Level WARNING
                    }
                }
                Write-Log -Message "Deleted $deleted old shadow copies." -Level SUCCESS
                Record-Action -Module 'ShadowCopyCleanup' -Action 'Delete' -Target 'Shadow Copies' -Result 'Completed' -FilesAffected $deleted
            }
        }
    } catch {
        Write-Log -Message "Shadow copy query failed: $($_.Exception.Message)" -Level INFO
    }
}

function Invoke-DevToolCacheCleanup {
    Write-SectionHeader -Title 'Developer Tool Cache Cleanup' -Risk 'Low'

    Write-Log -Message 'WHY SAFE: Package manager caches are re-downloaded on demand. No installed packages affected.' -Level DETAIL
    Write-Log -Message 'IMPACT: Next install/restore may take longer as packages are re-fetched.' -Level DETAIL

    $caches = @(
        @{ Name = 'npm';    Path = "$env:LOCALAPPDATA\npm-cache" },
        @{ Name = 'yarn';   Path = "$env:LOCALAPPDATA\Yarn\Cache" },
        @{ Name = 'pip';    Path = "$env:LOCALAPPDATA\pip\cache" },
        @{ Name = 'NuGet';  Path = "$env:LOCALAPPDATA\NuGet\v3-cache" },
        @{ Name = 'NuGet HTTP'; Path = "$env:LOCALAPPDATA\NuGet\plugins\netfx\CredentialProvider\http-cache" },
        @{ Name = 'cargo';  Path = "$env:USERPROFILE\.cargo\registry\cache" },
        @{ Name = 'Go Mod'; Path = "$env:LOCALAPPDATA\go\pkg\mod\cache\download" },
        @{ Name = 'Maven';  Path = "$env:USERPROFILE\.m2\repository" },
        @{ Name = 'Gradle'; Path = "$env:USERPROFILE\.gradle\caches" },
        @{ Name = 'Composer'; Path = "$env:LOCALAPPDATA\Composer\cache" }
    )

    $totalBytes = [long]0; $totalFiles = 0; $found = @()
    foreach ($c in $caches) {
        if (Test-Path $c.Path) {
            $r = Get-ScanResult -Path $c.Path -Recurse
            if ($r.Files -gt 0) {
                Write-Log -Message "Found $($c.Name) cache: $($r.Files) files ($(Format-FileSize $r.Bytes))" -Level INFO
                $totalBytes += $r.Bytes; $totalFiles += $r.Files
                $found += $c
            }
        }
    }

    if ($found.Count -eq 0) {
        Write-Log -Message 'No developer tool caches found.' -Level SUCCESS
        return
    }

    Write-Log -Message "Total developer caches: $(Format-FileSize $totalBytes) across $($found.Count) tools" -Level INFO

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would delete $totalFiles cached files ($(Format-FileSize $totalBytes))" -Level ACTION
        Record-Action -Module 'DevToolCaches' -Action 'WouldDelete' -Target 'Dev Caches' -Result 'DryRun' -BytesFreed $totalBytes -FilesAffected $totalFiles
    } else {
        $confirmed = Get-UserConfirmation -Message "Delete $totalFiles developer cache files ($(Format-FileSize $totalBytes))?"
        if ($confirmed) {
            foreach ($c in $found) {
                try {
                    Get-ChildItem $c.Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log -Message "Cleared $($c.Name) cache." -Level SUCCESS
                } catch {
                    Write-Log -Message "Could not fully clear $($c.Name) cache." -Level WARNING
                }
            }
            $Script:TotalBytesFreed += $totalBytes
            $Script:TotalFilesRemoved += $totalFiles
            Record-Action -Module 'DevToolCaches' -Action 'Delete' -Target 'Dev Caches' -Result 'Completed' -BytesFreed $totalBytes -FilesAffected $totalFiles
        }
    }
}

function Invoke-AppCacheCleanup {
    Write-SectionHeader -Title 'Application Cache Cleanup' -Risk 'Low'

    Write-Log -Message 'WHY SAFE: Only cached/temp data removed. App settings, accounts, and chat history preserved.' -Level DETAIL
    Write-Log -Message 'IMPACT: Apps may take slightly longer to start until caches rebuild.' -Level DETAIL
    Write-Log -Message 'Close the listed applications before cleaning for best results.' -Level WARNING

    $apps = @(
        @{ Name = 'Microsoft Teams (Classic)'; Paths = @(
            "$env:APPDATA\Microsoft\Teams\Cache",
            "$env:APPDATA\Microsoft\Teams\blob_storage",
            "$env:APPDATA\Microsoft\Teams\databases",
            "$env:APPDATA\Microsoft\Teams\GPUCache",
            "$env:APPDATA\Microsoft\Teams\IndexedDB",
            "$env:APPDATA\Microsoft\Teams\Local Storage",
            "$env:APPDATA\Microsoft\Teams\tmp"
        )},
        @{ Name = 'Microsoft Teams (New)'; Paths = @(
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
        )},
        @{ Name = 'Discord'; Paths = @(
            "$env:APPDATA\discord\Cache",
            "$env:APPDATA\discord\Code Cache",
            "$env:APPDATA\discord\GPUCache"
        )},
        @{ Name = 'Slack'; Paths = @(
            "$env:APPDATA\Slack\Cache",
            "$env:APPDATA\Slack\Code Cache",
            "$env:APPDATA\Slack\GPUCache"
        )},
        @{ Name = 'Spotify'; Paths = @(
            "$env:LOCALAPPDATA\Spotify\Storage"
        )},
        @{ Name = 'VS Code'; Paths = @(
            "$env:APPDATA\Code\Cache",
            "$env:APPDATA\Code\CachedData",
            "$env:APPDATA\Code\CachedExtensions",
            "$env:APPDATA\Code\CachedExtensionVSIXs",
            "$env:APPDATA\Code\Code Cache"
        )}
    )

    $totalBytes = [long]0; $totalFiles = 0; $foundApps = @()
    foreach ($app in $apps) {
        $appBytes = [long]0; $appFiles = 0
        foreach ($p in $app.Paths) {
            if (Test-Path $p) {
                $r = Get-ScanResult -Path $p -Recurse
                $appBytes += $r.Bytes; $appFiles += $r.Files
            }
        }
        if ($appFiles -gt 0) {
            Write-Log -Message "$($app.Name): $appFiles files ($(Format-FileSize $appBytes))" -Level INFO
            $totalBytes += $appBytes; $totalFiles += $appFiles
            $foundApps += $app
        }
    }

    if ($foundApps.Count -eq 0) {
        Write-Log -Message 'No application caches found.' -Level SUCCESS
        return
    }

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would delete $totalFiles cached files ($(Format-FileSize $totalBytes)) from $($foundApps.Count) apps" -Level ACTION
        Record-Action -Module 'AppCacheCleanup' -Action 'WouldDelete' -Target 'App Caches' -Result 'DryRun' -BytesFreed $totalBytes -FilesAffected $totalFiles
    } else {
        $confirmed = Get-UserConfirmation -Message "Delete caches for $($foundApps.Count) apps ($(Format-FileSize $totalBytes))? Close apps first for best results."
        if ($confirmed) {
            foreach ($app in $foundApps) {
                foreach ($p in $app.Paths) {
                    if (Test-Path $p) {
                        Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                Write-Log -Message "Cleared $($app.Name) cache." -Level SUCCESS
            }
            $Script:TotalBytesFreed += $totalBytes
            $Script:TotalFilesRemoved += $totalFiles
            Record-Action -Module 'AppCacheCleanup' -Action 'Delete' -Target 'App Caches' -Result 'Completed' -BytesFreed $totalBytes -FilesAffected $totalFiles
        }
    }
}

function Invoke-FontCacheRebuild {
    Write-SectionHeader -Title 'Font Cache Rebuild' -Risk 'Low'

    if (-not $Script:IsAdmin) {
        Write-Log -Message 'SKIPPED: Requires administrator privileges.' -Level WARNING
        return
    }

    Write-Log -Message 'WHY SAFE: Font cache is auto-rebuilt on next logon. Fixes garbled/missing font issues.' -Level DETAIL
    Write-Log -Message 'IMPACT: Fonts may appear briefly broken until cache rebuilds (usually seconds).' -Level DETAIL

    $fontCachePath = "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache"
    $fontCacheFiles = @()
    $totalBytes = [long]0

    if (Test-Path $fontCachePath) {
        $fontCacheFiles = Get-ChildItem $fontCachePath -File -ErrorAction SilentlyContinue
        if ($fontCacheFiles) {
            $totalBytes = ($fontCacheFiles | Measure-Object -Property Length -Sum).Sum
        }
    }

    # Also check FNTCACHE.DAT
    $fntCache = "$env:WINDIR\System32\FNTCACHE.DAT"
    if (Test-Path $fntCache) {
        $totalBytes += (Get-Item $fntCache -ErrorAction SilentlyContinue).Length
    }

    Write-Log -Message "Font cache size: $(Format-FileSize $totalBytes)" -Level INFO

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would stop FontCache service, clear cache, and restart." -Level ACTION
        Record-Action -Module 'FontCacheRebuild' -Action 'WouldRebuild' -Target 'Font Cache' -Result 'DryRun' -BytesFreed $totalBytes
    } else {
        $confirmed = Get-UserConfirmation -Message "Rebuild font cache ($(Format-FileSize $totalBytes))? Fixes font rendering issues."
        if ($confirmed) {
            try {
                Stop-Service FontCache -Force -ErrorAction SilentlyContinue
                Stop-Service FontCache3.0.0.0 -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                if (Test-Path $fontCachePath) {
                    Get-ChildItem $fontCachePath -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path $fntCache) {
                    Remove-Item $fntCache -Force -ErrorAction SilentlyContinue
                }
                Start-Service FontCache -ErrorAction SilentlyContinue
                $Script:TotalBytesFreed += $totalBytes
                Write-Log -Message "Font cache cleared. It will rebuild automatically." -Level SUCCESS
                Record-Action -Module 'FontCacheRebuild' -Action 'Rebuild' -Target 'Font Cache' -Result 'Completed' -BytesFreed $totalBytes
            } catch {
                Write-Log -Message "Font cache rebuild failed: $($_.Exception.Message)" -Level INFO
                Start-Service FontCache -ErrorAction SilentlyContinue
            }
        }
    }
}

function Invoke-DotNetCleanup {
    Write-SectionHeader -Title '.NET Native Image Cache Cleanup' -Risk 'Medium'

    if (-not $Script:IsAdmin) {
        Write-Log -Message 'SKIPPED: Requires administrator privileges.' -Level WARNING
        return
    }

    Write-Log -Message 'WHY SAFE: Native images are pre-compiled .NET assemblies. They auto-regenerate on first app launch.' -Level DETAIL
    Write-Log -Message 'IMPACT: .NET applications may start slower on first run until images recompile.' -Level DETAIL
    Write-Log -Message 'CAUTION: First launch of .NET apps will be slower. Not recommended on production servers.' -Level WARNING

    $ngenPaths = @(
        "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319",
        "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"
    )

    $totalBytes = [long]0; $totalFiles = 0
    $assemblyPaths = @(
        "$env:WINDIR\assembly\NativeImages_v4.0.30319_32",
        "$env:WINDIR\assembly\NativeImages_v4.0.30319_64"
    )

    foreach ($p in $assemblyPaths) {
        if (Test-Path $p) {
            $r = Get-ScanResult -Path $p -Recurse
            $totalBytes += $r.Bytes; $totalFiles += $r.Files
        }
    }

    if ($totalFiles -eq 0) {
        Write-Log -Message 'No .NET native image cache found.' -Level SUCCESS
        return
    }

    Write-Log -Message ".NET native image cache: $totalFiles files ($(Format-FileSize $totalBytes))" -Level SUCCESS

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Would clear .NET native image cache ($(Format-FileSize $totalBytes))" -Level ACTION
        Record-Action -Module 'DotNetCleanup' -Action 'WouldDelete' -Target '.NET NGen Cache' -Result 'DryRun' -BytesFreed $totalBytes -FilesAffected $totalFiles
    } else {
        $confirmed = Get-UserConfirmation -Message "Clear .NET native image cache ($(Format-FileSize $totalBytes))? .NET apps will recompile on next run."
        if ($confirmed) {
            foreach ($ngenDir in $ngenPaths) {
                $ngenExe = Join-Path $ngenDir 'ngen.exe'
                if (Test-Path $ngenExe) {
                    try {
                        Write-Log -Message "Running ngen queue cleanup via $ngenExe" -Level INFO
                        & $ngenExe executeQueuedItems 2>&1 | Out-Null
                    } catch {}
                }
            }
            foreach ($p in $assemblyPaths) {
                if (Test-Path $p) {
                    Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $Script:TotalBytesFreed += $totalBytes
            $Script:TotalFilesRemoved += $totalFiles
            Write-Log -Message "Cleared .NET native image cache ($(Format-FileSize $totalBytes))" -Level SUCCESS
            Record-Action -Module 'DotNetCleanup' -Action 'Delete' -Target '.NET NGen Cache' -Result 'Completed' -BytesFreed $totalBytes -FilesAffected $totalFiles
        }
    }
}

function Invoke-LargeFileFinder {
    Write-SectionHeader -Title 'Large File Finder (>500 MB)' -Risk 'None (read-only)'

    Write-Log -Message 'This module is READ-ONLY. No files will be modified or deleted.' -Level INFO
    Write-Log -Message 'WHY: Identifies large files consuming disk space so you can decide what to remove.' -Level DETAIL

    $systemDrive = $env:SystemDrive
    Write-Log -Message "Scanning user and common directories on $systemDrive for files larger than 500 MB..." -Level INFO

    $minSize = 500MB
    # Scan user-accessible directories with shallow depth for speed
    $scanTargets = @(
        @{ Path = "$env:USERPROFILE\Downloads";    Depth = 3 },
        @{ Path = "$env:USERPROFILE\Documents";    Depth = 3 },
        @{ Path = "$env:USERPROFILE\Desktop";      Depth = 2 },
        @{ Path = "$env:USERPROFILE\Videos";       Depth = 3 },
        @{ Path = "$env:USERPROFILE\AppData\Local\Temp"; Depth = 2 },
        @{ Path = "$systemDrive\Windows\Temp";     Depth = 1 },
        @{ Path = "$systemDrive\Windows\SoftwareDistribution"; Depth = 2 }
    )

    try {
        $largeFiles = @()
        foreach ($target in $scanTargets) {
            if (Test-Path $target.Path) {
                $found = Get-ChildItem $target.Path -File -Recurse -Depth $target.Depth -Force -ErrorAction SilentlyContinue |
                         Where-Object { $_.Length -ge $minSize }
                if ($found) { $largeFiles += $found }
            }
        }
        # Also check drive root for stray large files (depth 0 = root only)
        $rootFiles = Get-ChildItem "$systemDrive\" -File -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Length -ge $minSize }
        if ($rootFiles) { $largeFiles += $rootFiles }

        $largeFiles = $largeFiles | Sort-Object Length -Descending | Select-Object -First 25

        if (-not $largeFiles -or $largeFiles.Count -eq 0) {
            Write-Log -Message 'No files larger than 500 MB found.' -Level SUCCESS
            Record-Action -Module 'LargeFileFinder' -Action 'Analyze' -Target 'Large Files' -Result 'Completed'
            return
        }

        Write-Host ""
        Write-Host "    LARGE FILES ON $systemDrive" -ForegroundColor White
        Write-Host "    $([string]::new('-', 70))" -ForegroundColor DarkGray

        $totalLargeSize = [long]0
        foreach ($f in $largeFiles) {
            $sizeText = (Format-FileSize $f.Length).PadLeft(12)
            $age = [math]::Round(((Get-Date) - $f.LastWriteTime).TotalDays)
            $path = $f.FullName
            if ($path.Length -gt 55) { $path = '...' + $path.Substring($path.Length - 52) }
            Write-Host "    $sizeText  " -ForegroundColor Yellow -NoNewline
            Write-Host "${age}d ago  " -ForegroundColor DarkGray -NoNewline
            Write-Host $path -ForegroundColor Gray
            $totalLargeSize += $f.Length
        }

        Write-Host "    $([string]::new('-', 70))" -ForegroundColor DarkGray
        Write-Host "    Total: $(Format-FileSize $totalLargeSize) across $($largeFiles.Count) files" -ForegroundColor White
        Write-Host ""
        Write-Log -Message 'TIP: Review these files manually. Common culprits: VM images, ISOs, old backups, logs.' -Level DETAIL
    } catch {
        Write-Log -Message "Scan incomplete: $($_.Exception.Message)" -Level WARNING
    }

    Record-Action -Module 'LargeFileFinder' -Action 'Analyze' -Target 'Large Files' -Result 'Completed'
}

function Invoke-DuplicateFileFinder {
    Write-SectionHeader -Title 'Duplicate File Finder' -Risk 'None (read-only)'

    Write-Log -Message 'This module is READ-ONLY. No files will be modified or deleted.' -Level INFO
    Write-Log -Message 'WHY: Identifies duplicate files in common user directories wasting disk space.' -Level DETAIL
    Write-Log -Message 'METHOD: Groups files by size, then compares MD5 hashes for files >1MB.' -Level DETAIL

    $scanDirs = @(
        [Environment]::GetFolderPath('MyDocuments'),
        [Environment]::GetFolderPath('Desktop'),
        "$env:USERPROFILE\Downloads"
    )

    Write-Log -Message 'Scanning user directories for duplicate files >1 MB...' -Level INFO

    $allFiles = @()
    foreach ($dir in $scanDirs) {
        if (Test-Path $dir) {
            try {
                $files = Get-ChildItem $dir -File -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Length -ge 1MB }
                if ($files) { $allFiles += $files }
            } catch {}
        }
    }

    if ($allFiles.Count -lt 2) {
        Write-Log -Message 'Not enough large files to check for duplicates.' -Level SUCCESS
        Record-Action -Module 'DuplicateFileFinder' -Action 'Analyze' -Target 'Duplicates' -Result 'Completed'
        return
    }

    # Group by file size first (fast filter)
    $sizeGroups = $allFiles | Group-Object Length | Where-Object { $_.Count -ge 2 }

    if (-not $sizeGroups) {
        Write-Log -Message 'No potential duplicates found (no matching file sizes).' -Level SUCCESS
        Record-Action -Module 'DuplicateFileFinder' -Action 'Analyze' -Target 'Duplicates' -Result 'Completed'
        return
    }

    $duplicateSets = @()
    $dupeBytes = [long]0

    foreach ($group in $sizeGroups) {
        # Hash files in this size group
        $hashGroups = @{}
        foreach ($f in $group.Group) {
            try {
                $hash = (Get-FileHash $f.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
                if ($hash) {
                    if (-not $hashGroups.ContainsKey($hash)) { $hashGroups[$hash] = @() }
                    $hashGroups[$hash] += $f
                }
            } catch {}
        }

        foreach ($hk in $hashGroups.Keys) {
            if ($hashGroups[$hk].Count -ge 2) {
                $duplicateSets += @{ Hash = $hk; Files = $hashGroups[$hk] }
                $dupeBytes += ($hashGroups[$hk].Count - 1) * $hashGroups[$hk][0].Length
            }
        }
    }

    if ($duplicateSets.Count -eq 0) {
        Write-Log -Message 'No duplicate files found.' -Level SUCCESS
    } else {
        Write-Host ""
        Write-Host "    DUPLICATE FILES FOUND" -ForegroundColor White
        Write-Host "    $([string]::new('-', 70))" -ForegroundColor DarkGray

        $shown = 0
        foreach ($set in ($duplicateSets | Select-Object -First 10)) {
            $size = Format-FileSize $set.Files[0].Length
            Write-Host "    [$size] $($set.Files.Count) copies:" -ForegroundColor Yellow
            foreach ($f in $set.Files) {
                $path = $f.FullName
                if ($path.Length -gt 65) { $path = '...' + $path.Substring($path.Length - 62) }
                Write-Host "      - $path" -ForegroundColor Gray
            }
            $shown++
        }

        if ($duplicateSets.Count -gt 10) {
            Write-Host "    ... and $($duplicateSets.Count - 10) more sets." -ForegroundColor DarkGray
        }

        Write-Host "    $([string]::new('-', 70))" -ForegroundColor DarkGray
        Write-Host "    Reclaimable space from duplicates: $(Format-FileSize $dupeBytes)" -ForegroundColor White
        Write-Host ""
        Write-Log -Message 'TIP: Review manually and delete unnecessary copies.' -Level DETAIL
    }

    Record-Action -Module 'DuplicateFileFinder' -Action 'Analyze' -Target 'Duplicates' -Result 'Completed'
}

function Invoke-ScheduledTaskReview {
    Write-SectionHeader -Title 'Scheduled Task Review' -Risk 'None (read-only)'

    Write-Log -Message 'This module is READ-ONLY. No tasks will be modified or disabled.' -Level INFO
    Write-Log -Message 'WHY: Identifies suspicious or unnecessary scheduled tasks consuming resources.' -Level DETAIL

    # Known unnecessary/bloatware task patterns
    $flagPatterns = @(
        '*Adobe*Update*', '*Google*Update*', '*CCleaner*', '*Driver*Booster*',
        '*Brave*Update*', '*Opera*Update*', '*Avast*', '*AVG*',
        '*Baidu*', '*McAfee*', '*Norton*', '*IObit*',
        '*AdvancedSystemCare*', '*WiseRegistry*', '*Glary*'
    )

    $knownSafe = @(
        '\Microsoft\*', '\CreateExplorerShellUnelevatedTask'
    )

    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
                 Where-Object { $_.State -ne 'Disabled' }

        if (-not $tasks) {
            Write-Log -Message 'Could not retrieve scheduled tasks.' -Level SKIP
            return
        }

        Write-Host ""
        Write-Host "    ACTIVE SCHEDULED TASKS REVIEW" -ForegroundColor White
        Write-Host "    $([string]::new('-', 70))" -ForegroundColor DarkGray

        $flagged = @()
        $thirdParty = @()

        foreach ($task in $tasks) {
            $taskPath = $task.TaskPath + $task.TaskName
            $isMicrosoft = $task.TaskPath -like '\Microsoft\*'

            # Check against flag patterns
            $isFlag = $false
            foreach ($pattern in $flagPatterns) {
                if ($task.TaskName -like $pattern -or $task.TaskPath -like $pattern) {
                    $isFlag = $true
                    break
                }
            }

            if ($isFlag) {
                $flagged += $task
            } elseif (-not $isMicrosoft -and $task.TaskPath -ne '\') {
                $thirdParty += $task
            }
        }

        if ($flagged.Count -gt 0) {
            Write-Host "    FLAGGED TASKS (likely unnecessary):" -ForegroundColor Yellow
            foreach ($t in ($flagged | Select-Object -First 15)) {
                Write-Host "    [!] " -ForegroundColor Red -NoNewline
                Write-Host "$($t.TaskName)" -ForegroundColor White -NoNewline
                Write-Host "  ($($t.State))" -ForegroundColor DarkGray
                Write-Host "        Path: $($t.TaskPath)" -ForegroundColor Gray
            }
            Write-Host ""
        }

        if ($thirdParty.Count -gt 0) {
            Write-Host "    THIRD-PARTY TASKS (review recommended):" -ForegroundColor Cyan
            foreach ($t in ($thirdParty | Select-Object -First 15)) {
                Write-Host "    [?] " -ForegroundColor Cyan -NoNewline
                Write-Host "$($t.TaskName)" -ForegroundColor White -NoNewline
                Write-Host "  ($($t.State))" -ForegroundColor DarkGray
            }
            Write-Host ""
        }

        $totalActive = $tasks.Count
        Write-Host "    $([string]::new('-', 70))" -ForegroundColor DarkGray
        Write-Host "    Total active: $totalActive | Flagged: $($flagged.Count) | Third-party: $($thirdParty.Count)" -ForegroundColor White
        Write-Host ""

        if ($flagged.Count -gt 0) {
            Write-Log -Message "TIP: Disable flagged tasks via: Disable-ScheduledTask -TaskName '<name>'" -Level DETAIL
        }

    } catch {
        Write-Log -Message "Could not enumerate scheduled tasks: $($_.Exception.Message)" -Level WARNING
    }

    Record-Action -Module 'ScheduledTaskReview' -Action 'Analyze' -Target 'Scheduled Tasks' -Result 'Completed'
}


# -----------------------------------------------------------------------------
# SECTION 4b -- PRIVACY & EXTENDED CLEANUP MODULES
# -----------------------------------------------------------------------------

function Invoke-WindowsPrivacyCleanup {
    <#
    .SYNOPSIS
        Clears Windows privacy-related data including recent docs, jump lists,
        typed paths, Run dialog MRU, search history, and clipboard.
    #>
    Write-SectionHeader -Title 'Windows Privacy Cleanup' -Risk 'Low'

    Write-Log "WHAT: Clears Windows privacy traces -- recent documents, jump lists, typed paths, Run MRU, clipboard." -Level INFO
    Write-Log "WHY : These items reveal usage patterns and recently accessed files." -Level INFO
    Write-Log "IMPACT: Reduces privacy exposure without affecting system stability." -Level INFO
    Write-Host ""

    $totalItems = 0

    # Scan jump lists
    $jumpAutoPath = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
    $jumpCustomPath = "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
    $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"

    $jAuto = Get-ScanResult -Path $jumpAutoPath -Recurse
    $jCustom = Get-ScanResult -Path $jumpCustomPath -Recurse
    $totalBytes = $jAuto.Bytes + $jCustom.Bytes
    $totalFiles = $jAuto.Files + $jCustom.Files

    # Check registry MRU entries
    $regPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    )
    $mruCount = 0
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            try {
                $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
                if ($props) { $mruCount++ }
            } catch {}
        }
    }

    $totalItems = $totalFiles + $mruCount
    if ($totalItems -eq 0 -and $totalBytes -eq 0) {
        Write-Log "Nothing to clean. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles jump list files, $mruCount registry MRU locations." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would clear jump lists ($(Format-FileSize $totalBytes)), registry MRU entries, and clipboard." -Level ACTION
        Record-Action -Module 'WindowsPrivacyCleanup' -Action 'WouldDelete' -Target 'Privacy data' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Clear Windows privacy data ($totalItems items, $(Format-FileSize $totalBytes))?")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $errors = 0

    # Clear jump lists
    foreach ($jp in @($jumpAutoPath, $jumpCustomPath)) {
        if (Test-Path $jp) {
            try {
                Get-ChildItem -Path $jp -File -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log "Cleared: $jp" -Level DETAIL
            } catch { $errors++ }
        }
    }

    # Clear registry MRU entries
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            try {
                $item = Get-Item -Path $rp -ErrorAction SilentlyContinue
                foreach ($valName in $item.GetValueNames()) {
                    if ($valName -ne '(Default)' -and $valName -ne 'MRUListEx' -and $valName -ne 'MRUList') {
                        Remove-ItemProperty -Path $rp -Name $valName -Force -ErrorAction SilentlyContinue
                    }
                }
                Write-Log "Cleared MRU: $rp" -Level DETAIL
            } catch {
                Write-Log "Could not clear: $rp -- $($_.Exception.Message)" -Level WARNING
                $errors++
            }
        }
    }

    # Clear application MRU/history entries (FCleaner parity)
    $appMruPaths = @(
        @{ Path = 'HKCU:\Software\Microsoft\Terminal Server Client\Default'; Desc = 'Remote Desktop MRU'; Pattern = 'MRU*' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\RegEdit'; Desc = 'RegEdit last key'; Values = @('LastKey') }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Paint\Recent File List'; Desc = 'Paint recent files'; Pattern = '*' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Wordpad\Recent File List'; Desc = 'WordPad recent files'; Pattern = '*' }
        @{ Path = 'HKCU:\Software\Microsoft\MediaPlayer\Player\RecentFileList'; Desc = 'Windows Media Player recent'; Pattern = '*' }
    )
    foreach ($entry in $appMruPaths) {
        if (Test-Path $entry.Path) {
            try {
                $item = Get-Item -Path $entry.Path -ErrorAction SilentlyContinue
                if ($entry.ContainsKey('Values')) {
                    foreach ($vn in $entry.Values) {
                        if ($item.GetValueNames() -contains $vn) {
                            Remove-ItemProperty -Path $entry.Path -Name $vn -Force -ErrorAction SilentlyContinue
                        }
                    }
                } else {
                    foreach ($valName in $item.GetValueNames()) {
                        if ($valName -ne '(Default)') {
                            Remove-ItemProperty -Path $entry.Path -Name $valName -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                Write-Log "Cleared app MRU: $($entry.Desc)" -Level DETAIL
            } catch {
                Write-Log "Could not clear $($entry.Desc): $($_.Exception.Message)" -Level WARNING
                $errors++
            }
        }
    }

    # Clear clipboard
    try {
        Set-Clipboard -Value $null -ErrorAction SilentlyContinue
        Write-Log "Clipboard cleared." -Level DETAIL
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.Clipboard]::Clear()
            Write-Log "Clipboard cleared (Forms method)." -Level DETAIL
        } catch {
            Write-Log "Could not clear clipboard: $($_.Exception.Message)" -Level WARNING
        }
    }

    Record-Action -Module 'WindowsPrivacyCleanup' -Action 'Delete' -Target 'Privacy data' `
                  -Result 'Completed' -BytesFreed $totalBytes -FilesAffected $totalFiles
    Write-Log "Privacy cleanup complete. Cleared $(Format-FileSize $totalBytes) and $mruCount MRU locations." -Level SUCCESS
    if ($errors -gt 0) { $Script:TotalErrors += $errors }
}

function Invoke-BrowserPrivacyCleanup {
    <#
    .SYNOPSIS
        Clears browser privacy data (cookies, history, form data) from
        Chrome, Edge, Firefox, Opera, Brave, Vivaldi, and Waterfox.
    #>
    Write-SectionHeader -Title 'Browser Privacy Cleanup' -Risk 'Medium'

    Write-Log "WHAT: Removes cookies, browsing history, form data, and saved shortcuts from major browsers." -Level INFO
    Write-Log "WHY : These files contain sensitive browsing data and tracking cookies." -Level INFO
    Write-Log "IMPACT: You WILL be logged out of all websites in affected browsers." -Level INFO
    Write-Host ""

    $totalBytes = [long]0
    $totalFiles = 0
    $browserTargets = @()

    # Privacy-sensitive database files in each browser profile
    $privacyFiles = @('Cookies', 'Cookies-journal', 'History', 'History-journal',
                      'Web Data', 'Web Data-journal', 'Shortcuts', 'Shortcuts-journal',
                      'Top Sites', 'Top Sites-journal', 'Visited Links')

    # Chrome
    $chromeBase = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
    if (Test-Path $chromeBase) {
        foreach ($pf in $privacyFiles) {
            $fp = Join-Path $chromeBase $pf
            if (Test-Path $fp) {
                $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                if ($sz) {
                    $totalBytes += $sz; $totalFiles++
                    $browserTargets += @{ Path = $fp; Browser = 'Chrome'; File = $pf }
                }
            }
        }
    }

    # Edge
    $edgeBase = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
    if (Test-Path $edgeBase) {
        foreach ($pf in $privacyFiles) {
            $fp = Join-Path $edgeBase $pf
            if (Test-Path $fp) {
                $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                if ($sz) {
                    $totalBytes += $sz; $totalFiles++
                    $browserTargets += @{ Path = $fp; Browser = 'Edge'; File = $pf }
                }
            }
        }
    }

    # Opera
    $operaBase = "$env:APPDATA\Opera Software\Opera Stable"
    if (Test-Path $operaBase) {
        foreach ($pf in $privacyFiles) {
            $fp = Join-Path $operaBase $pf
            if (Test-Path $fp) {
                $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                if ($sz) {
                    $totalBytes += $sz; $totalFiles++
                    $browserTargets += @{ Path = $fp; Browser = 'Opera'; File = $pf }
                }
            }
        }
    }

    # Brave
    $braveBase = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
    if (Test-Path $braveBase) {
        foreach ($pf in $privacyFiles) {
            $fp = Join-Path $braveBase $pf
            if (Test-Path $fp) {
                $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                if ($sz) {
                    $totalBytes += $sz; $totalFiles++
                    $browserTargets += @{ Path = $fp; Browser = 'Brave'; File = $pf }
                }
            }
        }
    }

    # Vivaldi
    $vivaldiBase = "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
    if (Test-Path $vivaldiBase) {
        foreach ($pf in $privacyFiles) {
            $fp = Join-Path $vivaldiBase $pf
            if (Test-Path $fp) {
                $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                if ($sz) {
                    $totalBytes += $sz; $totalFiles++
                    $browserTargets += @{ Path = $fp; Browser = 'Vivaldi'; File = $pf }
                }
            }
        }
    }

    # Firefox
    $ffProfileRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfileRoot) {
        $ffDbs = @('cookies.sqlite', 'places.sqlite', 'formhistory.sqlite',
                   'cookies.sqlite-wal', 'places.sqlite-wal', 'formhistory.sqlite-wal')
        $ffProfiles = Get-ChildItem -Path $ffProfileRoot -Directory -Filter '*.default*' -ErrorAction SilentlyContinue
        foreach ($prof in $ffProfiles) {
            foreach ($db in $ffDbs) {
                $fp = Join-Path $prof.FullName $db
                if (Test-Path $fp) {
                    $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                    if ($sz) {
                        $totalBytes += $sz; $totalFiles++
                        $browserTargets += @{ Path = $fp; Browser = 'Firefox'; File = $db }
                    }
                }
            }
        }
    }

    # Waterfox (Firefox-based)
    $wfProfileRoot = "$env:LOCALAPPDATA\Waterfox\Profiles"
    if (Test-Path $wfProfileRoot) {
        $wfDbs = @('cookies.sqlite', 'places.sqlite', 'formhistory.sqlite',
                   'cookies.sqlite-wal', 'places.sqlite-wal', 'formhistory.sqlite-wal')
        $wfProfiles = Get-ChildItem -Path $wfProfileRoot -Directory -Filter '*.default*' -ErrorAction SilentlyContinue
        foreach ($prof in $wfProfiles) {
            foreach ($db in $wfDbs) {
                $fp = Join-Path $prof.FullName $db
                if (Test-Path $fp) {
                    $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                    if ($sz) {
                        $totalBytes += $sz; $totalFiles++
                        $browserTargets += @{ Path = $fp; Browser = 'Waterfox'; File = $db }
                    }
                }
            }
        }
    }

    if ($totalBytes -eq 0) {
        Write-Log "No browser privacy data found. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles browser privacy files." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $(Format-FileSize $totalBytes) of browser privacy data." -Level ACTION
        foreach ($bt in $browserTargets) {
            Write-Log "  [DRY-RUN] $($bt.Browser): $($bt.File)" -Level DETAIL
        }
        Record-Action -Module 'BrowserPrivacyCleanup' -Action 'WouldDelete' -Target 'Browser data' -Result 'DryRun'
        return
    }

    Write-Host ""
    Write-Host "    *** WARNING: This will log you out of ALL websites! ***" -ForegroundColor Red
    Write-Host "    Close all browsers before proceeding for best results." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Request-Confirmation "Delete $(Format-FileSize $totalBytes) of browser privacy data? (You WILL be logged out)")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $freed = [long]0
    $removed = 0
    $errors = 0

    foreach ($bt in $browserTargets) {
        try {
            $sz = (Get-Item $bt.Path -Force -ErrorAction SilentlyContinue).Length
            Remove-Item -Path $bt.Path -Force -ErrorAction Stop
            $freed += $sz
            $removed++
            Write-Log "Deleted: $($bt.Browser) -- $($bt.File)" -Level DETAIL
        } catch {
            $errors++
            Write-Log "Skipped (in use): $($bt.Browser) -- $($bt.File)" -Level DETAIL
        }
    }

    Record-Action -Module 'BrowserPrivacyCleanup' -Action 'Delete' -Target 'Browser privacy data' `
                  -Result 'Completed' -BytesFreed $freed -FilesAffected $removed
    Write-Log "Browser privacy cleanup complete. Removed $removed files, freed $(Format-FileSize $freed)." -Level SUCCESS
    if ($errors -gt 0) {
        Write-Log "$errors files skipped (browser may be running)." -Level WARNING
        $Script:TotalErrors += $errors
    }
}

function Invoke-OfficeCleanup {
    <#
    .SYNOPSIS
        Cleans Microsoft Office and LibreOffice temporary and cache files.
    #>
    Write-SectionHeader -Title 'Office Temp & Cache Cleanup' -Risk 'Low'

    Write-Log "WHAT: Removes Office file cache, unsaved file backups, and LibreOffice temp data." -Level INFO
    Write-Log "WHY : Office apps accumulate cache files that are safe to remove when apps are closed." -Level INFO
    Write-Log "IMPACT: Frees disk space from stale Office caches." -Level INFO
    Write-Host ""

    $totalBytes = [long]0
    $totalFiles = 0

    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
        "$env:LOCALAPPDATA\Microsoft\Office\UnsavedFiles",
        "$env:LOCALAPPDATA\Microsoft\OneNote\16.0\cache",
        "$env:APPDATA\LibreOffice\user\backup",
        "$env:APPDATA\LibreOffice\user\store"
    )

    foreach ($p in $paths) {
        $r = Get-ScanResult -Path $p -Recurse
        $totalBytes += $r.Bytes; $totalFiles += $r.Files
    }

    if ($totalBytes -eq 0) {
        Write-Log "No Office cache files found. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles Office cache files." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $(Format-FileSize $totalBytes) of Office cache data." -Level ACTION
        Record-Action -Module 'OfficeCleanup' -Action 'WouldDelete' -Target 'Office cache' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Delete $(Format-FileSize $totalBytes) of Office cache files?")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $moduleTotalFreed = [long]0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $result = Remove-SafeFiles -Path $p -ModuleName 'OfficeCleanup' `
                        -Description "Office/LibreOffice cache files" -Recurse
            $moduleTotalFreed += $result.BytesFreed
        }
    }

    Write-Log "Office cleanup complete. Freed $(Format-FileSize $moduleTotalFreed)." -Level SUCCESS
}

function Invoke-CloudStorageCleanup {
    <#
    .SYNOPSIS
        Cleans local caches and logs from cloud storage sync applications.
    #>
    Write-SectionHeader -Title 'Cloud Storage Cache Cleanup' -Risk 'Low'

    Write-Log "WHAT: Removes log files and caches from OneDrive, Google Drive, Dropbox, and iCloud." -Level INFO
    Write-Log "WHY : Cloud sync apps accumulate logs and crash reports that are safe to remove." -Level INFO
    Write-Log "IMPACT: Frees disk space without affecting synced files." -Level INFO
    Write-Host ""

    $totalBytes = [long]0
    $totalFiles = 0

    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
        "$env:LOCALAPPDATA\Google\DriveFS\Logs",
        "$env:LOCALAPPDATA\Dropbox\logs",
        "$env:APPDATA\Dropbox\crash_reports",
        "$env:LOCALAPPDATA\Apple Inc\iCloud\Logs"
    )

    foreach ($p in $paths) {
        $r = Get-ScanResult -Path $p -Recurse
        $totalBytes += $r.Bytes; $totalFiles += $r.Files
    }

    if ($totalBytes -eq 0) {
        Write-Log "No cloud storage cache files found. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles cloud storage log/cache files." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $(Format-FileSize $totalBytes) of cloud storage caches." -Level ACTION
        Record-Action -Module 'CloudStorageCleanup' -Action 'WouldDelete' -Target 'Cloud caches' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Delete $(Format-FileSize $totalBytes) of cloud storage log files?")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $moduleTotalFreed = [long]0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $result = Remove-SafeFiles -Path $p -ModuleName 'CloudStorageCleanup' `
                        -Description "Cloud sync app logs and caches" -Recurse
            $moduleTotalFreed += $result.BytesFreed
        }
    }

    Write-Log "Cloud storage cleanup complete. Freed $(Format-FileSize $moduleTotalFreed)." -Level SUCCESS
}

function Invoke-AdobeCleanup {
    <#
    .SYNOPSIS
        Cleans Adobe product caches and temporary files.
    #>
    Write-SectionHeader -Title 'Adobe Product Cache Cleanup' -Risk 'Low'

    Write-Log "WHAT: Removes Adobe Acrobat, Creative Cloud, and general Adobe cache files." -Level INFO
    Write-Log "WHY : Adobe products create substantial caches that persist after use." -Level INFO
    Write-Log "IMPACT: Frees disk space from stale Adobe caches." -Level INFO
    Write-Host ""

    $totalBytes = [long]0
    $totalFiles = 0

    $paths = @(
        "$env:LOCALAPPDATA\Adobe\Acrobat\DC\Cache",
        "$env:LOCALAPPDATA\Adobe\Creative Cloud\ACC"
    )

    foreach ($p in $paths) {
        $r = Get-ScanResult -Path $p -Recurse
        $totalBytes += $r.Bytes; $totalFiles += $r.Files
    }

    # Scan for Adobe temp files in TEMP directory
    if (Test-Path $env:TEMP) {
        try {
            $adobeTemp = Get-ChildItem -Path $env:TEMP -Filter 'Adobe*' -Directory -ErrorAction SilentlyContinue
            foreach ($d in $adobeTemp) {
                $r = Get-ScanResult -Path $d.FullName -Recurse
                $totalBytes += $r.Bytes; $totalFiles += $r.Files
                $paths += $d.FullName
            }
        } catch {}
    }

    # Scan generic Adobe cache dirs
    $adobeBase = "$env:LOCALAPPDATA\Adobe"
    if (Test-Path $adobeBase) {
        try {
            $cacheDirs = Get-ChildItem -Path $adobeBase -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '^Cache' }
            foreach ($d in $cacheDirs) {
                if ($d.FullName -notin $paths) {
                    $r = Get-ScanResult -Path $d.FullName -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    $paths += $d.FullName
                }
            }
        } catch {}
    }

    if ($totalBytes -eq 0) {
        Write-Log "No Adobe cache files found. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles Adobe cache files." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $(Format-FileSize $totalBytes) of Adobe caches." -Level ACTION
        Record-Action -Module 'AdobeCleanup' -Action 'WouldDelete' -Target 'Adobe cache' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Delete $(Format-FileSize $totalBytes) of Adobe cache files?")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $moduleTotalFreed = [long]0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $result = Remove-SafeFiles -Path $p -ModuleName 'AdobeCleanup' `
                        -Description "Adobe product cache files" -Recurse
            $moduleTotalFreed += $result.BytesFreed
        }
    }

    Write-Log "Adobe cleanup complete. Freed $(Format-FileSize $moduleTotalFreed)." -Level SUCCESS
}

function Invoke-JavaCleanup {
    <#
    .SYNOPSIS
        Cleans Java runtime deployment caches, temp files, and logs.
    #>
    Write-SectionHeader -Title 'Java Cache Cleanup' -Risk 'Low'

    Write-Log "WHAT: Removes Java deployment cache, WebStart temp files, and log files." -Level INFO
    Write-Log "WHY : Java caches applets and web-start apps that are rarely needed after use." -Level INFO
    Write-Log "IMPACT: Frees disk space from stale Java runtime data." -Level INFO
    Write-Host ""

    $totalBytes = [long]0
    $totalFiles = 0

    $paths = @(
        "$env:LOCALAPPDATA\Sun\Java\Deployment\cache",
        "$env:LOCALAPPDATA\Sun\Java\Deployment\tmp",
        "$env:LOCALAPPDATA\Sun\Java\Deployment\log",
        "$env:USERPROFILE\.java",
        "$env:LOCALAPPDATA\Oracle\Java"
    )

    foreach ($p in $paths) {
        $r = Get-ScanResult -Path $p -Recurse
        $totalBytes += $r.Bytes; $totalFiles += $r.Files
    }

    if ($totalBytes -eq 0) {
        Write-Log "No Java cache files found. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles Java cache files." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $(Format-FileSize $totalBytes) of Java caches." -Level ACTION
        Record-Action -Module 'JavaCleanup' -Action 'WouldDelete' -Target 'Java cache' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Delete $(Format-FileSize $totalBytes) of Java cache files?")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $moduleTotalFreed = [long]0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $result = Remove-SafeFiles -Path $p -ModuleName 'JavaCleanup' `
                        -Description "Java runtime cache and temp files" -Recurse
            $moduleTotalFreed += $result.BytesFreed
        }
    }

    Write-Log "Java cleanup complete. Freed $(Format-FileSize $moduleTotalFreed)." -Level SUCCESS
}

function Invoke-ChkdskFragmentCleanup {
    <#
    .SYNOPSIS
        Removes orphaned file fragments left by chkdsk in FOUND.xxx directories.
    #>
    Write-SectionHeader -Title 'Chkdsk File Fragments' -Risk 'Low'

    Write-Log "WHAT: Removes .chk fragment files from FOUND.xxx directories on the system drive." -Level INFO
    Write-Log "WHY : These are orphaned file fragments created by chkdsk that are rarely recoverable." -Level INFO
    Write-Log "IMPACT: Frees space from disk-check debris." -Level INFO
    Write-Host ""

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Requires administrator privileges." -Level WARNING
        Record-Action -Module 'ChkdskFragments' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    $totalBytes = [long]0
    $totalFiles = 0

    # Scan for found.* directories at system drive root
    $sysDrive = $env:SystemDrive
    try {
        $foundDirs = Get-ChildItem -Path "$sysDrive\" -Directory -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '^found\.\d+$' }
        foreach ($d in $foundDirs) {
            $r = Get-ScanResult -Path $d.FullName -Recurse
            $totalBytes += $r.Bytes; $totalFiles += $r.Files
        }
    } catch {}

    if ($totalBytes -eq 0) {
        Write-Log "No chkdsk fragments found. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles chkdsk fragment files." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $(Format-FileSize $totalBytes) of chkdsk fragments." -Level ACTION
        Record-Action -Module 'ChkdskFragments' -Action 'WouldDelete' -Target 'Chkdsk fragments' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Delete $(Format-FileSize $totalBytes) of chkdsk file fragments?")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $moduleTotalFreed = [long]0
    foreach ($d in $foundDirs) {
        if (Test-Path $d.FullName) {
            $result = Remove-SafeFiles -Path $d.FullName -ModuleName 'ChkdskFragments' `
                        -Description "Orphaned chkdsk file fragments" -Recurse
            $moduleTotalFreed += $result.BytesFreed
            # Try to remove the empty directory too
            try {
                $remaining = Get-ChildItem -Path $d.FullName -Force -ErrorAction SilentlyContinue
                if (-not $remaining -or $remaining.Count -eq 0) {
                    Remove-Item -Path $d.FullName -Force -ErrorAction SilentlyContinue
                    Write-Log "Removed empty directory: $($d.FullName)" -Level DETAIL
                }
            } catch {}
        }
    }

    Write-Log "Chkdsk fragment cleanup complete. Freed $(Format-FileSize $moduleTotalFreed)." -Level SUCCESS
}

function Invoke-IISLogCleanup {
    <#
    .SYNOPSIS
        Cleans IIS web server log files older than 30 days.
    #>
    Write-SectionHeader -Title 'IIS Log File Cleanup' -Risk 'Low'

    Write-Log "WHAT: Removes IIS log files older than 30 days." -Level INFO
    Write-Log "WHY : IIS logs accumulate rapidly and old entries are rarely needed for diagnostics." -Level INFO
    Write-Log "IMPACT: Frees disk space while keeping recent logs for troubleshooting." -Level INFO
    Write-Host ""

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Requires administrator privileges." -Level WARNING
        Record-Action -Module 'IISLogCleanup' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    $iisRoot = "$env:SystemDrive\inetpub"
    if (-not (Test-Path $iisRoot)) {
        Write-Log "IIS is not installed (inetpub not found). Skipping." -Level SKIP
        Record-Action -Module 'IISLogCleanup' -Action 'Skip' -Target 'N/A' -Result 'IIS not installed'
        return
    }

    $logPath = "$env:SystemDrive\inetpub\logs\LogFiles"
    if (-not (Test-Path $logPath)) {
        Write-Log "IIS log directory not found. Skipping." -Level SKIP
        return
    }

    $r = Get-ScanResult -Path $logPath -MinAgeDays 30 -Recurse
    $totalBytes = $r.Bytes
    $totalFiles = $r.Files

    if ($totalBytes -eq 0) {
        Write-Log "No IIS log files older than 30 days found. Skipping." -Level SUCCESS
        return
    }

    Write-Log "Found: $(Format-FileSize $totalBytes) in $totalFiles IIS log files (>30 days old)." -Level INFO

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would delete $(Format-FileSize $totalBytes) of old IIS logs." -Level ACTION
        Record-Action -Module 'IISLogCleanup' -Action 'WouldDelete' -Target 'IIS logs' -Result 'DryRun'
        return
    }

    if (-not (Request-Confirmation "Delete $(Format-FileSize $totalBytes) of IIS log files older than 30 days?")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    $result = Remove-SafeFiles -Path $logPath -ModuleName 'IISLogCleanup' `
                -Description "IIS log files older than 30 days" -MinAgeDays 30 -Recurse
    Write-Log "IIS log cleanup complete. Freed $(Format-FileSize $result.BytesFreed)." -Level SUCCESS
}

function Invoke-FreeSpaceWiper {
    <#
    .SYNOPSIS
        Securely wipes free disk space using the built-in cipher.exe utility.
    #>
    Write-SectionHeader -Title 'Free Space Secure Wipe' -Risk 'Medium'

    Write-Log "WHAT: Overwrites free disk space using Windows cipher.exe /w to prevent file recovery." -Level INFO
    Write-Log "WHY : Deleted files can be recovered until their disk sectors are overwritten." -Level INFO
    Write-Log "IMPACT: Previously deleted data becomes unrecoverable. This can take HOURS on large drives." -Level INFO
    Write-Host ""

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Requires administrator privileges." -Level WARNING
        Record-Action -Module 'FreeSpaceWiper' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    $sysDrive = $env:SystemDrive
    try {
        $driveInfo = Get-PSDrive -Name ($sysDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
        $freeGB = [math]::Round($driveInfo.Free / 1GB, 2)
        $freeBytes = $driveInfo.Free
    } catch {
        $freeGB = 0
        $freeBytes = [long]0
    }

    Write-Log "System drive: $sysDrive" -Level INFO
    Write-Log "Free space: $freeGB GB" -Level INFO
    Write-Log "Estimated time: ~1 minute per GB of free space ($freeGB minutes+)." -Level INFO
    Write-Host ""

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would wipe $freeGB GB of free space on $sysDrive using cipher.exe /w." -Level ACTION
        Record-Action -Module 'FreeSpaceWiper' -Action 'WouldWipe' -Target "$sysDrive free space" -Result 'DryRun'
        return
    }

    Write-Host "    *** WARNING: This operation can take HOURS on large drives! ***" -ForegroundColor Red
    Write-Host "    Free space to wipe: $freeGB GB" -ForegroundColor Yellow
    Write-Host "    The system will remain usable but disk I/O will be heavy." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Request-Confirmation "Securely wipe $freeGB GB of free space on $sysDrive`? This may take a very long time.")) {
        Write-Log "Skipped by user." -Level SKIP
        return
    }

    Write-Log "Starting free space wipe on $sysDrive -- this will take a long time..." -Level INFO
    try {
        $wipeDir = "$sysDrive\"
        $process = Start-Process -FilePath 'cipher.exe' -ArgumentList "/w:$wipeDir" `
                     -NoNewWindow -PassThru -Wait
        if ($process.ExitCode -eq 0) {
            Record-Action -Module 'FreeSpaceWiper' -Action 'Wipe' -Target "$sysDrive free space" -Result 'Completed'
            Write-Log "Free space wipe completed successfully." -Level SUCCESS
        } else {
            Write-Log "cipher.exe exited with code $($process.ExitCode)." -Level WARNING
        }
    } catch {
        Write-Log "Error during free space wipe: $($_.Exception.Message)" -Level ERROR
        $Script:TotalErrors++
    }
}

function Invoke-RestorePointAnalysis {
    <#
    .SYNOPSIS
        Analyzes system restore points and shadow copy storage usage (read-only).
    #>
    Write-SectionHeader -Title 'Restore Point Analysis' -Risk 'None (read-only)'

    Write-Log "WHAT: Lists system restore points and reports shadow copy storage usage." -Level INFO
    Write-Log "WHY : Helps understand disk usage by System Restore and recovery data." -Level INFO
    Write-Log "IMPACT: Read-only analysis -- no changes are made." -Level INFO
    Write-Host ""

    if (-not $Script:IsAdmin) {
        Write-Log "SKIPPED: Requires administrator privileges (for vssadmin)." -Level WARNING
        Record-Action -Module 'RestorePointAnalysis' -Action 'Skip' -Target 'N/A' -Result 'NotAdmin'
        return
    }

    # List restore points
    try {
        $restorePoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        if ($restorePoints -and $restorePoints.Count -gt 0) {
            Write-Log "System Restore Points: $($restorePoints.Count) found." -Level INFO
            Write-Host ""
            Write-Host ("  " + 'SEQ'.PadRight(6) + 'DATE'.PadRight(24) + 'TYPE'.PadRight(20) + 'DESCRIPTION') -ForegroundColor White
            Write-Host "  $([string]::new('-', 78))" -ForegroundColor DarkGray

            foreach ($rp in $restorePoints) {
                $rpDate = try { $rp.ConvertToDateTime($rp.CreationTime).ToString('yyyy-MM-dd HH:mm:ss') } catch { $rp.CreationTime }
                $rpType = switch ($rp.RestorePointType) {
                    0  { 'Application Install' }
                    1  { 'Application Uninstall' }
                    10 { 'Device Install' }
                    12 { 'Modify Settings' }
                    13 { 'Cancelled Operation' }
                    default { "Type $($rp.RestorePointType)" }
                }
                $seq = "$($rp.SequenceNumber)".PadRight(6)
                $desc = if ($rp.Description.Length -gt 30) { $rp.Description.Substring(0,30) } else { $rp.Description }
                Write-Host "  $seq$($rpDate.ToString().PadRight(24))$($rpType.PadRight(20))$desc" -ForegroundColor Gray
            }

            Write-Host ""

            # Oldest and newest
            $dates = $restorePoints | ForEach-Object {
                try { $_.ConvertToDateTime($_.CreationTime) } catch { Get-Date }
            }
            $oldest = ($dates | Sort-Object | Select-Object -First 1).ToString('yyyy-MM-dd')
            $newest = ($dates | Sort-Object -Descending | Select-Object -First 1).ToString('yyyy-MM-dd')
            Write-Log "Oldest restore point: $oldest" -Level INFO
            Write-Log "Newest restore point: $newest" -Level INFO
        } else {
            Write-Log "No system restore points found." -Level INFO
        }
    } catch {
        Write-Log "Could not enumerate restore points: $($_.Exception.Message)" -Level WARNING
    }

    # Shadow copy storage info
    try {
        $vssOutput = & vssadmin list shadowstorage 2>&1
        if ($vssOutput) {
            Write-Host ""
            Write-Log "Shadow Copy Storage:" -Level INFO
            foreach ($line in $vssOutput) {
                $lineStr = "$line".Trim()
                if ($lineStr.Length -gt 0) {
                    Write-Host "    $lineStr" -ForegroundColor Gray
                }
            }
        }
    } catch {
        Write-Log "Could not query shadow storage: $($_.Exception.Message)" -Level WARNING
    }

    Write-Host ""
    Record-Action -Module 'RestorePointAnalysis' -Action 'Analyze' -Target 'Restore Points' -Result 'Completed'
    Write-Log "Restore point analysis complete." -Level SUCCESS
}

# -----------------------------------------------------------------------------
# SECTION 5 -- INTERACTIVE MENU
# -----------------------------------------------------------------------------

function Show-InteractiveMenu {
    <#
    .SYNOPSIS
        Displays a categorized numbered menu for selecting modules.
    #>
    Write-Host ""
    Write-Host "  Select modules to run:" -ForegroundColor White

    $index = 1
    $menuMap = @{}
    $lastCategory = ''

    foreach ($key in $Script:AllModules.Keys) {
        $mod = $Script:AllModules[$key]

        # Print category header when it changes
        if ($mod.Category -ne $lastCategory) {
            $lastCategory = $mod.Category
            $catLabel = switch ($mod.Category) {
                'Basic'    { 'BASIC CLEANUP' }
                'Advanced' { 'ADVANCED CLEANUP' }
                'Tools'    { 'SYSTEM TOOLS' }
                'Analysis' { 'ANALYSIS (READ-ONLY)' }
                'Privacy'  { 'PRIVACY' }
                default    { $mod.Category.ToUpper() }
            }
            Write-Host ""
            Write-Host "    -- $catLabel --" -ForegroundColor DarkCyan
        }

        $adminTag = if ($mod.RequiresAdmin -and -not $Script:IsAdmin) { ' [Requires Admin]' } else { '' }
        $color = if ($mod.RequiresAdmin -and -not $Script:IsAdmin) { 'DarkGray' } else { 'White' }
        $numLabel = "$index".PadLeft(2)

        Write-Host "    [$numLabel] " -ForegroundColor Cyan -NoNewline
        Write-Host "$($mod.Name)$adminTag" -ForegroundColor $color -NoNewline
        Write-Host "  (Risk: $($mod.Risk))" -ForegroundColor DarkGray
        $menuMap["$index"] = $key
        $index++
    }

    Write-Host ""
    Write-Host "    [ A] " -ForegroundColor Green -NoNewline
    Write-Host "Run ALL modules" -ForegroundColor White
    Write-Host "    [ Q] " -ForegroundColor Red -NoNewline
    Write-Host "Quit" -ForegroundColor White
    Write-Host ""
    Write-Host "  Enter selection (comma-separated, e.g. 1,3,5): " -ForegroundColor Yellow -NoNewline
    $selection = Read-Host

    if ($selection -match '^[Qq]') { return @() }
    if ($selection -match '^[Aa]') { return @($Script:AllModules.Keys) }

    $selected = @()
    foreach ($num in ($selection -split ',')) {
        $num = $num.Trim()
        if ($menuMap.ContainsKey($num)) {
            $selected += $menuMap[$num]
        }
    }

    return $selected
}

function Show-RetroUI {
    <#
    .SYNOPSIS
        Full-screen retro terminal UI with keyboard navigation.
    .DESCRIPTION
        Draws a DOS/Norton Commander-style text interface with bordered panels,
        green-on-black color scheme, and arrow-key module selection.
    #>

    $originalBg = $Host.UI.RawUI.BackgroundColor
    $originalFg = $Host.UI.RawUI.ForegroundColor

    try {
        # Set retro colors
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.UI.RawUI.ForegroundColor = 'Green'
        Clear-Host

        $width = [Math]::Min($Host.UI.RawUI.WindowSize.Width, 100)
        $innerW = $width - 4

        # Build module list with categories
        $moduleList = [System.Collections.Generic.List[PSCustomObject]]::new()
        $categories = @('Basic','Advanced','Privacy','Tools','Analysis')
        foreach ($cat in $categories) {
            # Add category header
            $moduleList.Add([PSCustomObject]@{ Key = "CAT_$cat"; Name = "=== $($cat.ToUpper()) ==="; Category = $cat; IsHeader = $true; Selected = $false })
            foreach ($key in $Script:AllModules.Keys) {
                $mod = $Script:AllModules[$key]
                if ($mod.Category -eq $cat) {
                    $moduleList.Add([PSCustomObject]@{ Key = $key; Name = $mod.Name; Category = $cat; IsHeader = $false; Selected = $true })
                }
            }
        }

        $cursorPos = 1  # Start on first actual module (skip first header)
        # Find first non-header item
        for ($i = 0; $i -lt $moduleList.Count; $i++) {
            if (-not $moduleList[$i].IsHeader) { $cursorPos = $i; break }
        }

        $scrollOffset = 0
        $maxVisible = $Host.UI.RawUI.WindowSize.Height - 14  # Leave room for header/footer
        if ($maxVisible -lt 10) { $maxVisible = 10 }

        $running = $true

        while ($running) {
            $Host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, 0)

            # Top border
            $topBar = '+' + ('-' * ($width - 2)) + '+'
            Write-Host $topBar -ForegroundColor DarkGreen

            # Title
            $title = "SYSTEM MAINTENANCE TOOL v$($Script:Version)"
            $pad = [Math]::Max(0, ($innerW - $title.Length) / 2)
            Write-Host ('| ' + (' ' * [Math]::Floor($pad)) + $title + (' ' * [Math]::Ceiling($pad)) + ' |') -ForegroundColor Green

            $subtitle = "[ Retro Terminal Interface ]"
            $pad2 = [Math]::Max(0, ($innerW - $subtitle.Length) / 2)
            Write-Host ('| ' + (' ' * [Math]::Floor($pad2)) + $subtitle + (' ' * [Math]::Ceiling($pad2)) + ' |') -ForegroundColor DarkGreen

            Write-Host $topBar -ForegroundColor DarkGreen

            # Instructions
            $instrLine = "  UP/DOWN: Navigate | SPACE: Toggle | A: All | N: None | ENTER: Run | ESC: Quit"
            if ($instrLine.Length -gt $innerW) { $instrLine = $instrLine.Substring(0, $innerW) }
            Write-Host ('| ' + $instrLine.PadRight($innerW) + ' |') -ForegroundColor Yellow

            Write-Host ('+' + ('-' * ($width - 2)) + '+') -ForegroundColor DarkGreen

            # Module list
            $visibleEnd = [Math]::Min($scrollOffset + $maxVisible, $moduleList.Count)

            for ($i = $scrollOffset; $i -lt $visibleEnd; $i++) {
                $item = $moduleList[$i]
                $isCursor = ($i -eq $cursorPos)

                if ($item.IsHeader) {
                    # Category header - centered, highlighted
                    $headerText = $item.Name
                    $hPad = [Math]::Max(0, ($innerW - $headerText.Length) / 2)
                    $line = (' ' * [Math]::Floor($hPad)) + $headerText + (' ' * [Math]::Ceiling($hPad))
                    Write-Host ('| ' + $line.Substring(0, [Math]::Min($line.Length, $innerW)).PadRight($innerW) + ' |') -ForegroundColor Cyan
                } else {
                    $check = if ($item.Selected) { '[X]' } else { '[ ]' }
                    $pointer = if ($isCursor) { '>' } else { ' ' }
                    $displayName = "$pointer $check $($item.Name)"

                    # Get risk info
                    $risk = if ($Script:AllModules.Contains($item.Key)) { $Script:AllModules[$item.Key].Risk } else { '' }
                    $riskText = if ($risk) { "($risk)" } else { '' }

                    $maxNameLen = $innerW - $riskText.Length - 2
                    if ($displayName.Length -gt $maxNameLen) {
                        $displayName = $displayName.Substring(0, $maxNameLen - 3) + '...'
                    }
                    $lineText = ($displayName + (' ' * [Math]::Max(1, $maxNameLen - $displayName.Length)) + $riskText).PadRight($innerW)
                    if ($lineText.Length -gt $innerW) { $lineText = $lineText.Substring(0, $innerW) }

                    $fg = if ($isCursor) { 'Black' } else { 'Green' }
                    $bg = if ($isCursor) { 'Green' } else { 'Black' }

                    Write-Host '| ' -ForegroundColor DarkGreen -NoNewline
                    Write-Host $lineText -ForegroundColor $fg -BackgroundColor $bg -NoNewline
                    Write-Host ' |' -ForegroundColor DarkGreen
                }
            }

            # Fill remaining lines
            $remaining = $maxVisible - ($visibleEnd - $scrollOffset)
            for ($f = 0; $f -lt $remaining; $f++) {
                Write-Host ('| ' + (' ' * $innerW) + ' |') -ForegroundColor DarkGreen
            }

            # Bottom panel with status
            Write-Host ('+' + ('-' * ($width - 2)) + '+') -ForegroundColor DarkGreen
            $selectedCount = ($moduleList | Where-Object { -not $_.IsHeader -and $_.Selected }).Count
            $totalCount = ($moduleList | Where-Object { -not $_.IsHeader }).Count
            $statusLine = "  Selected: $selectedCount / $totalCount modules"
            if ($DryRun) { $statusLine += "  |  MODE: DRY-RUN" }
            if ($Sound) { $statusLine += "  |  SOUND: ON" }
            if ($statusLine.Length -gt $innerW) { $statusLine = $statusLine.Substring(0, $innerW) }
            Write-Host ('| ' + $statusLine.PadRight($innerW) + ' |') -ForegroundColor Yellow
            Write-Host ('+' + ('-' * ($width - 2)) + '+') -ForegroundColor DarkGreen

            # Read key
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

            switch ($key.VirtualKeyCode) {
                38 {  # Up arrow
                    do {
                        $cursorPos--
                        if ($cursorPos -lt 0) { $cursorPos = $moduleList.Count - 1 }
                    } while ($moduleList[$cursorPos].IsHeader)

                    if ($cursorPos -lt $scrollOffset) { $scrollOffset = $cursorPos }
                    Play-RetroSound -Type 'ScanTick'
                }
                40 {  # Down arrow
                    do {
                        $cursorPos++
                        if ($cursorPos -ge $moduleList.Count) { $cursorPos = 0 }
                    } while ($moduleList[$cursorPos].IsHeader)

                    if ($cursorPos -ge ($scrollOffset + $maxVisible)) { $scrollOffset = $cursorPos - $maxVisible + 1 }
                    Play-RetroSound -Type 'ScanTick'
                }
                32 {  # Space - toggle selection
                    if (-not $moduleList[$cursorPos].IsHeader) {
                        $moduleList[$cursorPos].Selected = -not $moduleList[$cursorPos].Selected
                        Play-RetroSound -Type 'ActionStart'
                    }
                }
                65 {  # 'A' - select all
                    foreach ($item in $moduleList) { if (-not $item.IsHeader) { $item.Selected = $true } }
                    Play-RetroSound -Type 'ScanComplete'
                }
                78 {  # 'N' - deselect all
                    foreach ($item in $moduleList) { if (-not $item.IsHeader) { $item.Selected = $false } }
                    Play-RetroSound -Type 'Warning'
                }
                13 {  # Enter - run selected
                    $running = $false
                    Play-RetroSound -Type 'ScanStart'
                }
                27 {  # Escape - quit
                    # Restore colors
                    $Host.UI.RawUI.BackgroundColor = $originalBg
                    $Host.UI.RawUI.ForegroundColor = $originalFg
                    Clear-Host
                    Write-Host "Cancelled by user." -ForegroundColor Yellow
                    return @()
                }
            }
        }

        # Restore colors
        $Host.UI.RawUI.BackgroundColor = $originalBg
        $Host.UI.RawUI.ForegroundColor = $originalFg
        Clear-Host

        # Return selected module keys
        $selected = @($moduleList | Where-Object { -not $_.IsHeader -and $_.Selected } | ForEach-Object { $_.Key })
        return $selected

    } catch {
        # Restore colors on error
        $Host.UI.RawUI.BackgroundColor = $originalBg
        $Host.UI.RawUI.ForegroundColor = $originalFg
        Clear-Host
        Write-Log "RetroUI error: $($_.Exception.Message). Falling back to standard menu." -Level WARNING
        return Show-InteractiveMenu
    }
}

# -----------------------------------------------------------------------------
# SECTION 6 -- SUMMARY REPORT
# -----------------------------------------------------------------------------

function Write-SummaryReport {
    <#
    .SYNOPSIS
        Generates the final summary including actions taken, space freed, and recommendations.
    #>
    $elapsed = (Get-Date) - $Script:StartTime

    $separator = [string]::new([char]0x2550, 70)
    Write-Host ""
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "  MAINTENANCE SUMMARY REPORT" -ForegroundColor White
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""

    # Results
    $peakWS = [math]::Round([System.Diagnostics.Process]::GetCurrentProcess().PeakWorkingSet64 / 1MB, 1)
    $curWS  = [math]::Round([System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64 / 1MB, 1)

    Write-Host "  Duration        : $($elapsed.ToString('mm\:ss'))" -ForegroundColor Gray
    Write-Host "  Mode            : $(if ($DryRun) { 'DRY-RUN (no changes made)' } else { 'LIVE' })" -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Green' })
    Write-Host "  Disk Freed      : $(Format-FileSize $Script:TotalBytesFreed)" -ForegroundColor Green
    Write-Host "  Files Processed : $($Script:TotalFilesRemoved)" -ForegroundColor Gray
    Write-Host "  Errors          : $($Script:TotalErrors)" -ForegroundColor $(if ($Script:TotalErrors -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  Actions Logged  : $($Script:ActionLog.Count)" -ForegroundColor Gray
    Write-Host "  Resources       : $Script:CoresAllocated cores | RAM peak ${peakWS} MB / current ${curWS} MB" -ForegroundColor Gray
    Write-Host ""

    # Action log table
    if ($Script:ActionLog.Count -gt 0) {
        Write-Host "  Actions Taken:" -ForegroundColor White
        Write-Host "  $([string]::new('-', 66))" -ForegroundColor DarkGray
        foreach ($action in $Script:ActionLog) {
            $marker = switch ($action.Result) {
                'Completed' { '[OK]' }
                'DryRun'    { '[--]' }
                'NotAdmin'  { '[!!]' }
                default     { '[??]' }
            }
            $color = switch ($action.Result) {
                'Completed' { 'Green' }
                'DryRun'    { 'Yellow' }
                'NotAdmin'  { 'DarkYellow' }
                default     { 'Gray' }
            }
            Write-Host "  $marker " -ForegroundColor $color -NoNewline
            Write-Host "$($action.Module.PadRight(18)) $($action.Action.PadRight(14)) $($action.Target)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # Recommendations
    Write-Host "  Recommendations:" -ForegroundColor White
    Write-Host "  $([string]::new('-', 66))" -ForegroundColor DarkGray

    if (-not $Script:IsAdmin) {
        Write-Host "  * Re-run as Administrator for full functionality." -ForegroundColor Yellow
    }

    Write-Host "  * Schedule this tool monthly for ongoing maintenance." -ForegroundColor Gray
    Write-Host "  * Review startup items flagged by the Startup Analysis module." -ForegroundColor Gray
    Write-Host "  * Consider running Windows Disk Cleanup for deeper system cleanup." -ForegroundColor Gray
    Write-Host ""

    # Log file reference
    Write-Host "  Full log: $Script:LogFile" -ForegroundColor DarkGray
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""

    # Write summary to log file
    Write-Log "=== SUMMARY ===" -Level SECTION -NoConsole
    Write-Log "Duration: $($elapsed.ToString('mm\:ss'))" -Level INFO -NoConsole
    Write-Log "Mode: $(if ($DryRun) { 'DRY-RUN' } else { 'LIVE' })" -Level INFO -NoConsole
    Write-Log "Disk Freed: $(Format-FileSize $Script:TotalBytesFreed)" -Level INFO -NoConsole
    Write-Log "Files Processed: $($Script:TotalFilesRemoved)" -Level INFO -NoConsole
    Write-Log "Errors: $($Script:TotalErrors)" -Level INFO -NoConsole
    Write-Log "Resources: $Script:CoresAllocated/$Script:CpuCores cores, Priority=$Script:ProcessPriority, PeakRAM=${peakWS}MB" -Level INFO -NoConsole

    # Export action log to CSV alongside the text log
    if ($Script:ActionLog.Count -gt 0) {
        $csvPath = $Script:LogFile -replace '\.log$', '_actions.csv'
        $Script:ActionLog | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Log "Action log exported to: $csvPath" -Level INFO -NoConsole
    }
}

# -----------------------------------------------------------------------------
# SECTION 7 -- PRE-SCAN ENGINE
# -----------------------------------------------------------------------------

function Get-ScanResult {
    <#
    .SYNOPSIS
        Scans a folder and returns file count and total size without deleting anything.
    #>
    param([string]$Path, [int]$MinAgeDays = 0, [switch]$Recurse)

    if (-not (Test-Path $Path)) { return @{ Files = 0; Bytes = [long]0 } }

    try {
        $getParams = @{ Path = $Path; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
        if ($Recurse) { $getParams['Recurse'] = $true }
        $files = Get-ChildItem @getParams

        if ($MinAgeDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-$MinAgeDays)
            $files = $files | Where-Object { $_.LastWriteTime -lt $cutoff }
        }

        if (-not $files) { return @{ Files = 0; Bytes = [long]0 } }

        $measure = $files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
        return @{ Files = [int]$measure.Count; Bytes = [long]$measure.Sum }
    } catch {
        return @{ Files = 0; Bytes = [long]0 }
    }
}

function Invoke-PreScan {
    <#
    .SYNOPSIS
        Scans all selected modules and returns a results array for the summary table.
    #>
    param([string[]]$ModuleList)

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    $scanTotal = $ModuleList.Count
    $scanIndex = 0

    Play-RetroSound -Type 'ScanStart'

    foreach ($mod in $ModuleList) {
        $scanIndex++
        $modName = if ($Script:AllModules.Contains($mod)) { $Script:AllModules[$mod].Name } else { $mod }
        Write-ProgressBar -Current $scanIndex -Total $scanTotal -Activity "Scanning $modName"

        switch ($mod) {
            'TempFiles' {
                $totalBytes = [long]0; $totalFiles = 0
                $paths = @($env:TEMP, "$env:WINDIR\Temp", "$env:LOCALAPPDATA\Temp")
                foreach ($p in $paths) {
                    $r = Get-ScanResult -Path $p -MinAgeDays 2 -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                }
                $results.Add([PSCustomObject]@{
                    Module   = 'Temp Files'
                    Key      = 'TempFiles'
                    Files    = $totalFiles
                    Size     = $totalBytes
                    SizeText = Format-FileSize $totalBytes
                    Type     = 'Cleanup'
                    Status   = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'WindowsUpdate' {
                $wuPath = "$env:WINDIR\SoftwareDistribution\Download"
                if ($Script:IsAdmin -and (Test-Path $wuPath)) {
                    $r = Get-ScanResult -Path $wuPath -Recurse
                    $results.Add([PSCustomObject]@{
                        Module = 'Windows Update Cache'; Key = 'WindowsUpdate'
                        Files = $r.Files; Size = $r.Bytes; SizeText = Format-FileSize $r.Bytes
                        Type = 'Cleanup'; Status = if ($r.Bytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Windows Update Cache'; Key = 'WindowsUpdate'
                        Files = 0; Size = [long]0; SizeText = '--'
                        Type = 'Cleanup'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } else { 'Clean' }
                    })
                }
            }
            'RecycleBin' {
                $rbSize = [long]0; $rbCount = 0
                try {
                    $shell = New-Object -ComObject Shell.Application
                    $bin = $shell.NameSpace(0x0A)
                    $rbCount = $bin.Items().Count
                    # Estimate size from all recycle bin folders
                    Get-ChildItem -Path "$env:SystemDrive\`$Recycle.Bin" -Recurse -Force -File -ErrorAction SilentlyContinue |
                        ForEach-Object { $rbSize += $_.Length }
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
                } catch {}
                $results.Add([PSCustomObject]@{
                    Module = 'Recycle Bin'; Key = 'RecycleBin'
                    Files = $rbCount; Size = $rbSize; SizeText = Format-FileSize $rbSize
                    Type = 'Cleanup'; Status = if ($rbCount -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'BrowserCache' {
                $totalBytes = [long]0; $totalFiles = 0
                $cachePaths = @(
                    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
                    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage",
                    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
                    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage",
                    "$env:APPDATA\Opera Software\Opera Stable\Cache",
                    "$env:APPDATA\Opera Software\Opera Stable\Code Cache",
                    "$env:APPDATA\Opera Software\Opera Stable\Service Worker\CacheStorage",
                    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache",
                    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Code Cache",
                    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Service Worker\CacheStorage",
                    "$env:LOCALAPPDATA\Vivaldi\User Data\Default\Cache",
                    "$env:LOCALAPPDATA\Vivaldi\User Data\Default\Code Cache",
                    "$env:LOCALAPPDATA\Vivaldi\User Data\Default\Service Worker\CacheStorage"
                )
                foreach ($p in $cachePaths) {
                    $r = Get-ScanResult -Path $p -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                }
                # Firefox
                $ffPath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
                if (Test-Path $ffPath) {
                    Get-ChildItem $ffPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        $r = Get-ScanResult -Path (Join-Path $_.FullName 'cache2\entries') -Recurse
                        $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    }
                }
                # Waterfox
                $wfPath = "$env:LOCALAPPDATA\Waterfox\Profiles"
                if (Test-Path $wfPath) {
                    Get-ChildItem $wfPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        $r = Get-ScanResult -Path (Join-Path $_.FullName 'cache2\entries') -Recurse
                        $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    }
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Browser Caches'; Key = 'BrowserCache'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'EventLogs' {
                $logSize = [long]0; $logCount = 0
                if ($Script:IsAdmin) {
                    try {
                        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
                                Where-Object { $_.FileSize -gt 50MB -and $_.LogName -notmatch 'Security' }
                        if ($logs) {
                            $logCount = $logs.Count
                            $logs | ForEach-Object { $logSize += $_.FileSize }
                        }
                    } catch {}
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Event Logs (>50 MB)'; Key = 'EventLogs'
                    Files = $logCount; Size = $logSize; SizeText = if (-not $Script:IsAdmin) { '--' } else { Format-FileSize $logSize }
                    Type = 'Cleanup'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } elseif ($logSize -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'DiskCleanup' {
                $results.Add([PSCustomObject]@{
                    Module = 'Windows Disk Cleanup'; Key = 'DiskCleanup'
                    Files = 0; Size = [long]0; SizeText = '(system tool)'
                    Type = 'Tool'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } else { 'Available' }
                })
            }
            'StartupAnalysis' {
                $count = 0
                try {
                    $regPaths = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')
                    foreach ($rp in $regPaths) {
                        if (Test-Path $rp) {
                            $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
                            $count += ($props.PSObject.Properties | Where-Object {
                                $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')
                            }).Count
                        }
                    }
                    $sf = [Environment]::GetFolderPath('Startup')
                    if (Test-Path $sf) { $count += (Get-ChildItem $sf -File -ErrorAction SilentlyContinue).Count }
                } catch {}
                $results.Add([PSCustomObject]@{
                    Module = 'Startup Programs'; Key = 'StartupAnalysis'
                    Files = $count; Size = [long]0; SizeText = "$count items"
                    Type = 'Analysis'; Status = 'Ready'
                })
            }
            'ServiceAnalysis' {
                $count = 0
                $reviewNames = @('DiagTrack','dmwappushservice','MapsBroker','lfsvc','RetailDemo',
                                 'wisvc','WMPNetworkSvc','WerSvc','XblAuthManager','XblGameSave',
                                 'XboxNetApiSvc','XboxGipSvc')
                try {
                    $count = (Get-Service -ErrorAction SilentlyContinue |
                              Where-Object { $_.Status -eq 'Running' -and $_.Name -in $reviewNames }).Count
                } catch {}
                $results.Add([PSCustomObject]@{
                    Module = 'Service Review'; Key = 'ServiceAnalysis'
                    Files = $count; Size = [long]0; SizeText = "$count flagged"
                    Type = 'Analysis'; Status = 'Ready'
                })
            }
            'PrefetchCleanup' {
                $pfPath = "$env:WINDIR\Prefetch"
                if ($Script:IsAdmin -and (Test-Path $pfPath)) {
                    $r = Get-ScanResult -Path $pfPath -Filter '*.pf' -Recurse:$false
                    $results.Add([PSCustomObject]@{
                        Module = 'Prefetch Files'; Key = 'PrefetchCleanup'
                        Files = $r.Files; Size = $r.Bytes; SizeText = Format-FileSize $r.Bytes
                        Type = 'Cleanup'; Status = if ($r.Bytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Prefetch Files'; Key = 'PrefetchCleanup'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = 'Needs Admin'
                    })
                }
            }
            'DeliveryOptimization' {
                $doPath = "$env:WINDIR\SoftwareDistribution\DeliveryOptimization"
                if ($Script:IsAdmin -and (Test-Path $doPath)) {
                    $r = Get-ScanResult -Path $doPath -Recurse
                    $results.Add([PSCustomObject]@{
                        Module = 'Delivery Optimization'; Key = 'DeliveryOptimization'
                        Files = $r.Files; Size = $r.Bytes; SizeText = Format-FileSize $r.Bytes
                        Type = 'Cleanup'; Status = if ($r.Bytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Delivery Optimization'; Key = 'DeliveryOptimization'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } else { 'Clean' }
                    })
                }
            }
            'WindowsOldCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $woPaths = @("$env:SystemDrive\Windows.old", "$env:SystemDrive\`$Windows.~BT", "$env:SystemDrive\`$Windows.~WS")
                if ($Script:IsAdmin) {
                    foreach ($p in $woPaths) {
                        if (Test-Path $p) {
                            $r = Get-ScanResult -Path $p -Recurse
                            $totalBytes += $r.Bytes; $totalFiles += $r.Files
                        }
                    }
                    $results.Add([PSCustomObject]@{
                        Module = 'Windows.old'; Key = 'WindowsOldCleanup'
                        Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                        Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Windows.old'; Key = 'WindowsOldCleanup'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = 'Needs Admin'
                    })
                }
            }
            'CrashDumps' {
                $totalBytes = [long]0; $totalFiles = 0
                $dumpPaths = @(
                    "$env:WINDIR\Minidump",
                    "$env:WINDIR\LiveKernelReports",
                    "$env:LOCALAPPDATA\CrashDumps"
                )
                $memDmp = "$env:WINDIR\MEMORY.DMP"
                if (Test-Path $memDmp) {
                    try {
                        $fi = Get-Item $memDmp -ErrorAction SilentlyContinue
                        $totalBytes += $fi.Length; $totalFiles++
                    } catch {}
                }
                foreach ($p in $dumpPaths) {
                    if (Test-Path $p) {
                        $r = Get-ScanResult -Path $p -Recurse
                        $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    }
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Crash Dumps'; Key = 'CrashDumps'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'InstallerCleanup' {
                $pcPath = "$env:WINDIR\Installer\`$PatchCache`$"
                if ($Script:IsAdmin -and (Test-Path $pcPath)) {
                    $r = Get-ScanResult -Path $pcPath -Recurse
                    $results.Add([PSCustomObject]@{
                        Module = 'Installer Patch Cache'; Key = 'InstallerCleanup'
                        Files = $r.Files; Size = $r.Bytes; SizeText = Format-FileSize $r.Bytes
                        Type = 'Cleanup'; Status = if ($r.Bytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Installer Patch Cache'; Key = 'InstallerCleanup'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } else { 'Clean' }
                    })
                }
            }
            'ShaderCache' {
                $totalBytes = [long]0; $totalFiles = 0
                $shaderPaths = @(
                    "$env:LOCALAPPDATA\NVIDIA\DXCache",
                    "$env:LOCALAPPDATA\NVIDIA\GLCache",
                    "$env:LOCALAPPDATA\AMD\DxCache",
                    "$env:LOCALAPPDATA\AMD\GLCache",
                    "$env:LOCALAPPDATA\D3DSCache",
                    "$env:LOCALAPPDATA\Intel\ShaderCache",
                    "$env:LOCALAPPDATA\UnrealEngine\CommonCache"
                )
                foreach ($p in $shaderPaths) {
                    if (Test-Path $p) {
                        $r = Get-ScanResult -Path $p -Recurse
                        $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    }
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Shader Cache'; Key = 'ShaderCache'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'ThumbCacheCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $thumbDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
                if (Test-Path $thumbDir) {
                    try {
                        $dbFiles = Get-ChildItem $thumbDir -Filter 'thumbcache_*.db' -File -ErrorAction SilentlyContinue
                        $icFiles = Get-ChildItem $thumbDir -Filter 'iconcache_*.db' -File -ErrorAction SilentlyContinue
                        $allFiles = @()
                        if ($dbFiles) { $allFiles += $dbFiles }
                        if ($icFiles) { $allFiles += $icFiles }
                        foreach ($f in $allFiles) {
                            $totalBytes += $f.Length; $totalFiles++
                        }
                    } catch {}
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Thumbnail Cache'; Key = 'ThumbCacheCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'ComponentStoreCleanup' {
                if ($Script:IsAdmin) {
                    # Quick estimate via WinSxS folder size
                    $winsxs = "$env:WINDIR\WinSxS"
                    $sizeEstimate = [long]0
                    try {
                        # Use DISM to analyze; if unavailable, fall back to folder scan
                        $dismResult = & dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
                        $reclaimLine = $dismResult | Where-Object { $_ -match 'Reclaimable.*:\s+([\d.]+)\s+(GB|MB|KB)' }
                        if ($reclaimLine -and $Matches) {
                            $val = [double]$Matches[1]
                            $sizeEstimate = switch ($Matches[2]) {
                                'GB' { [long]($val * 1GB) }
                                'MB' { [long]($val * 1MB) }
                                'KB' { [long]($val * 1KB) }
                            }
                        }
                    } catch {}
                    $results.Add([PSCustomObject]@{
                        Module = 'Component Store'; Key = 'ComponentStoreCleanup'
                        Files = 0; Size = $sizeEstimate; SizeText = if ($sizeEstimate -gt 0) { Format-FileSize $sizeEstimate } else { 'Run DISM' }
                        Type = 'System'; Status = if ($sizeEstimate -gt 0) { 'Recoverable' } else { 'Available' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Component Store'; Key = 'ComponentStoreCleanup'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'System'; Status = 'Needs Admin'
                    })
                }
            }
            'DNSCacheFlush' {
                $entryCount = 0
                try {
                    $entries = Get-DnsClientCache -ErrorAction SilentlyContinue
                    if ($entries) { $entryCount = @($entries).Count }
                } catch {}
                $results.Add([PSCustomObject]@{
                    Module = 'DNS Cache'; Key = 'DNSCacheFlush'
                    Files = $entryCount; Size = [long]0; SizeText = "$entryCount entries"
                    Type = 'Network'; Status = 'Available'
                })
            }
            'WindowsStoreCache' {
                $totalBytes = [long]0; $totalFiles = 0
                $storeCachePaths = @(
                    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache",
                    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\TempState"
                )
                foreach ($p in $storeCachePaths) {
                    if (Test-Path $p) {
                        $r = Get-ScanResult -Path $p -Recurse
                        $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    }
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Store Cache'; Key = 'WindowsStoreCache'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'SystemHealthCheck' {
                $results.Add([PSCustomObject]@{
                    Module = 'System Health'; Key = 'SystemHealthCheck'
                    Files = 0; Size = [long]0; SizeText = '-- Info --'
                    Type = 'Analysis'; Status = 'Ready'
                })
            }
            'NetworkAnalysis' {
                $results.Add([PSCustomObject]@{
                    Module = 'Network Analysis'; Key = 'NetworkAnalysis'
                    Files = 0; Size = [long]0; SizeText = '-- Info --'
                    Type = 'Analysis'; Status = 'Ready'
                })
            }
            'ErrorReporting' {
                $totalBytes = [long]0; $totalFiles = 0
                $werPaths = @(
                    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
                    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                    "$env:ProgramData\Microsoft\Windows\WER\Temp"
                )
                if ($Script:IsAdmin) {
                    foreach ($p in $werPaths) {
                        if (Test-Path $p) {
                            $r = Get-ScanResult -Path $p -Recurse
                            $totalBytes += $r.Bytes; $totalFiles += $r.Files
                        }
                    }
                    $results.Add([PSCustomObject]@{
                        Module = 'Error Reports'; Key = 'ErrorReporting'
                        Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                        Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Error Reports'; Key = 'ErrorReporting'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = 'Needs Admin'
                    })
                }
            }
            'WindowsLogFiles' {
                $totalBytes = [long]0; $totalFiles = 0
                $cutoff = (Get-Date).AddDays(-30)
                if ($Script:IsAdmin) {
                    $logDirs = @("$env:WINDIR\Logs\CBS","$env:WINDIR\Logs\DISM","$env:WINDIR\Logs\WindowsUpdate","$env:WINDIR\Panther")
                    foreach ($d in $logDirs) {
                        if (Test-Path $d) {
                            try {
                                $old = Get-ChildItem $d -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }
                                if ($old) { $totalBytes += ($old | Measure-Object -Property Length -Sum).Sum; $totalFiles += $old.Count }
                            } catch {}
                        }
                    }
                    $results.Add([PSCustomObject]@{
                        Module = 'Diagnostic Logs'; Key = 'WindowsLogFiles'
                        Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                        Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Diagnostic Logs'; Key = 'WindowsLogFiles'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = 'Needs Admin'
                    })
                }
            }
            'DefenderCache' {
                $totalBytes = [long]0; $totalFiles = 0
                if ($Script:IsAdmin) {
                    $defPaths = @(
                        "$env:ProgramData\Microsoft\Windows Defender\Scans\History",
                        "$env:ProgramData\Microsoft\Windows Defender\Scans\MetaStore",
                        "$env:ProgramData\Microsoft\Windows Defender\LocalCopy"
                    )
                    foreach ($p in $defPaths) {
                        if (Test-Path $p) {
                            $r = Get-ScanResult -Path $p -Recurse
                            $totalBytes += $r.Bytes; $totalFiles += $r.Files
                        }
                    }
                    $results.Add([PSCustomObject]@{
                        Module = 'Defender Cache'; Key = 'DefenderCache'
                        Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                        Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Defender Cache'; Key = 'DefenderCache'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = 'Needs Admin'
                    })
                }
            }
            'SearchIndexCleanup' {
                $searchPath = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
                if ($Script:IsAdmin -and (Test-Path $searchPath)) {
                    $r = Get-ScanResult -Path $searchPath -Recurse
                    $results.Add([PSCustomObject]@{
                        Module = 'Search Index'; Key = 'SearchIndexCleanup'
                        Files = $r.Files; Size = $r.Bytes; SizeText = Format-FileSize $r.Bytes
                        Type = 'System'; Status = if ($r.Bytes -gt 10MB) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Search Index'; Key = 'SearchIndexCleanup'
                        Files = 0; Size = [long]0; SizeText = if (-not $Script:IsAdmin) { '-- N/A --' } else { '0 bytes' }
                        Type = 'System'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } else { 'Clean' }
                    })
                }
            }
            'ShadowCopyCleanup' {
                if ($Script:IsAdmin) {
                    $count = 0
                    try {
                        $shadows = Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue
                        if ($shadows) { $count = @($shadows).Count }
                    } catch {}
                    $results.Add([PSCustomObject]@{
                        Module = 'Shadow Copies'; Key = 'ShadowCopyCleanup'
                        Files = $count; Size = [long]0; SizeText = "$count snapshots"
                        Type = 'System'; Status = if ($count -gt 1) { 'Available' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Shadow Copies'; Key = 'ShadowCopyCleanup'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'System'; Status = 'Needs Admin'
                    })
                }
            }
            'DevToolCaches' {
                $totalBytes = [long]0; $totalFiles = 0
                $devPaths = @(
                    "$env:LOCALAPPDATA\npm-cache",
                    "$env:LOCALAPPDATA\Yarn\Cache",
                    "$env:LOCALAPPDATA\pip\cache",
                    "$env:LOCALAPPDATA\NuGet\v3-cache",
                    "$env:USERPROFILE\.cargo\registry\cache",
                    "$env:USERPROFILE\.m2\repository",
                    "$env:USERPROFILE\.gradle\caches",
                    "$env:LOCALAPPDATA\go\pkg\mod\cache\download"
                )
                foreach ($p in $devPaths) {
                    if (Test-Path $p) {
                        $r = Get-ScanResult -Path $p -Recurse
                        $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    }
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Dev Tool Caches'; Key = 'DevToolCaches'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'AppCacheCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $appCachePaths = @(
                    "$env:APPDATA\Microsoft\Teams\Cache",
                    "$env:APPDATA\Microsoft\Teams\blob_storage",
                    "$env:APPDATA\Microsoft\Teams\GPUCache",
                    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache",
                    "$env:APPDATA\discord\Cache",
                    "$env:APPDATA\discord\Code Cache",
                    "$env:APPDATA\Slack\Cache",
                    "$env:APPDATA\Slack\Code Cache",
                    "$env:LOCALAPPDATA\Spotify\Storage",
                    "$env:APPDATA\Code\Cache",
                    "$env:APPDATA\Code\CachedData",
                    "$env:APPDATA\Code\Code Cache"
                )
                foreach ($p in $appCachePaths) {
                    if (Test-Path $p) {
                        $r = Get-ScanResult -Path $p -Recurse
                        $totalBytes += $r.Bytes; $totalFiles += $r.Files
                    }
                }
                $results.Add([PSCustomObject]@{
                    Module = 'App Caches'; Key = 'AppCacheCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'FontCacheRebuild' {
                $totalBytes = [long]0
                if ($Script:IsAdmin) {
                    $fcPath = "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache"
                    if (Test-Path $fcPath) {
                        $r = Get-ScanResult -Path $fcPath -Recurse:$false
                        $totalBytes += $r.Bytes
                    }
                    $fnt = "$env:WINDIR\System32\FNTCACHE.DAT"
                    if (Test-Path $fnt) { try { $totalBytes += (Get-Item $fnt -ErrorAction SilentlyContinue).Length } catch {} }
                    $results.Add([PSCustomObject]@{
                        Module = 'Font Cache'; Key = 'FontCacheRebuild'
                        Files = 0; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                        Type = 'System'; Status = 'Available'
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = 'Font Cache'; Key = 'FontCacheRebuild'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'System'; Status = 'Needs Admin'
                    })
                }
            }
            'DotNetCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                if ($Script:IsAdmin) {
                    $niPaths = @(
                        "$env:WINDIR\assembly\NativeImages_v4.0.30319_32",
                        "$env:WINDIR\assembly\NativeImages_v4.0.30319_64"
                    )
                    foreach ($p in $niPaths) {
                        if (Test-Path $p) {
                            $r = Get-ScanResult -Path $p -Recurse
                            $totalBytes += $r.Bytes; $totalFiles += $r.Files
                        }
                    }
                    $results.Add([PSCustomObject]@{
                        Module = '.NET NGen Cache'; Key = 'DotNetCleanup'
                        Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                        Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                    })
                } else {
                    $results.Add([PSCustomObject]@{
                        Module = '.NET NGen Cache'; Key = 'DotNetCleanup'
                        Files = 0; Size = [long]0; SizeText = '-- N/A --'
                        Type = 'Cleanup'; Status = 'Needs Admin'
                    })
                }
            }
            'LargeFileFinder' {
                $results.Add([PSCustomObject]@{
                    Module = 'Large File Finder'; Key = 'LargeFileFinder'
                    Files = 0; Size = [long]0; SizeText = '-- Info --'
                    Type = 'Analysis'; Status = 'Ready'
                })
            }
            'DuplicateFileFinder' {
                $results.Add([PSCustomObject]@{
                    Module = 'Duplicate Finder'; Key = 'DuplicateFileFinder'
                    Files = 0; Size = [long]0; SizeText = '-- Info --'
                    Type = 'Analysis'; Status = 'Ready'
                })
            }
            'ScheduledTaskReview' {
                $count = 0
                try {
                    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' }
                    if ($tasks) { $count = @($tasks).Count }
                } catch {}
                $results.Add([PSCustomObject]@{
                    Module = 'Task Review'; Key = 'ScheduledTaskReview'
                    Files = $count; Size = [long]0; SizeText = "$count tasks"
                    Type = 'Analysis'; Status = 'Ready'
                })
            }
            'WindowsPrivacyCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $jumpAutoPath = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
                $jumpCustomPath = "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
                foreach ($p in @($jumpAutoPath, $jumpCustomPath)) {
                    $r = Get-ScanResult -Path $p -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Privacy Cleanup'; Key = 'WindowsPrivacyCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'BrowserPrivacyCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $privacyFiles = @('Cookies', 'History', 'Web Data', 'Shortcuts')
                $browsers = @(
                    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default",
                    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
                    "$env:APPDATA\Opera Software\Opera Stable",
                    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default",
                    "$env:LOCALAPPDATA\Vivaldi\User Data\Default"
                )
                foreach ($b in $browsers) {
                    foreach ($pf in $privacyFiles) {
                        $fp = Join-Path $b $pf
                        if (Test-Path $fp) {
                            $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                            if ($sz) { $totalBytes += $sz; $totalFiles++ }
                        }
                    }
                }
                $ffRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
                if (Test-Path $ffRoot) {
                    $ffProfiles = Get-ChildItem -Path $ffRoot -Directory -Filter '*.default*' -ErrorAction SilentlyContinue
                    foreach ($prof in $ffProfiles) {
                        foreach ($db in @('cookies.sqlite','places.sqlite','formhistory.sqlite')) {
                            $fp = Join-Path $prof.FullName $db
                            if (Test-Path $fp) {
                                $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                                if ($sz) { $totalBytes += $sz; $totalFiles++ }
                            }
                        }
                    }
                }
                $wfRoot = "$env:LOCALAPPDATA\Waterfox\Profiles"
                if (Test-Path $wfRoot) {
                    $wfProfiles = Get-ChildItem -Path $wfRoot -Directory -Filter '*.default*' -ErrorAction SilentlyContinue
                    foreach ($prof in $wfProfiles) {
                        foreach ($db in @('cookies.sqlite','places.sqlite','formhistory.sqlite')) {
                            $fp = Join-Path $prof.FullName $db
                            if (Test-Path $fp) {
                                $sz = (Get-Item $fp -Force -ErrorAction SilentlyContinue).Length
                                if ($sz) { $totalBytes += $sz; $totalFiles++ }
                            }
                        }
                    }
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Browser Privacy'; Key = 'BrowserPrivacyCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'OfficeCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $paths = @(
                    "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
                    "$env:LOCALAPPDATA\Microsoft\Office\UnsavedFiles",
                    "$env:LOCALAPPDATA\Microsoft\OneNote\16.0\cache",
                    "$env:APPDATA\LibreOffice\user\backup",
                    "$env:APPDATA\LibreOffice\user\store"
                )
                foreach ($p in $paths) {
                    $r = Get-ScanResult -Path $p -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Office Cache'; Key = 'OfficeCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'CloudStorageCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $paths = @(
                    "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
                    "$env:LOCALAPPDATA\Google\DriveFS\Logs",
                    "$env:LOCALAPPDATA\Dropbox\logs",
                    "$env:APPDATA\Dropbox\crash_reports",
                    "$env:LOCALAPPDATA\Apple Inc\iCloud\Logs"
                )
                foreach ($p in $paths) {
                    $r = Get-ScanResult -Path $p -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Cloud Caches'; Key = 'CloudStorageCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'AdobeCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $paths = @(
                    "$env:LOCALAPPDATA\Adobe\Acrobat\DC\Cache",
                    "$env:LOCALAPPDATA\Adobe\Creative Cloud\ACC"
                )
                foreach ($p in $paths) {
                    $r = Get-ScanResult -Path $p -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Adobe Cache'; Key = 'AdobeCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'JavaCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $paths = @(
                    "$env:LOCALAPPDATA\Sun\Java\Deployment\cache",
                    "$env:LOCALAPPDATA\Sun\Java\Deployment\tmp",
                    "$env:LOCALAPPDATA\Sun\Java\Deployment\log",
                    "$env:USERPROFILE\.java",
                    "$env:LOCALAPPDATA\Oracle\Java"
                )
                foreach ($p in $paths) {
                    $r = Get-ScanResult -Path $p -Recurse
                    $totalBytes += $r.Bytes; $totalFiles += $r.Files
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Java Cache'; Key = 'JavaCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = Format-FileSize $totalBytes
                    Type = 'Cleanup'; Status = if ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'ChkdskFragments' {
                $totalBytes = [long]0; $totalFiles = 0
                if ($Script:IsAdmin) {
                    try {
                        $foundDirs = Get-ChildItem -Path "$env:SystemDrive\" -Directory -Force -ErrorAction SilentlyContinue |
                                     Where-Object { $_.Name -match '^found\.\d+$' }
                        foreach ($d in $foundDirs) {
                            $r = Get-ScanResult -Path $d.FullName -Recurse
                            $totalBytes += $r.Bytes; $totalFiles += $r.Files
                        }
                    } catch {}
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Chkdsk Fragments'; Key = 'ChkdskFragments'
                    Files = $totalFiles; Size = $totalBytes; SizeText = if ($Script:IsAdmin) { Format-FileSize $totalBytes } else { '--' }
                    Type = 'Cleanup'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } elseif ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'IISLogCleanup' {
                $totalBytes = [long]0; $totalFiles = 0
                $logPath = "$env:SystemDrive\inetpub\logs\LogFiles"
                if ($Script:IsAdmin -and (Test-Path $logPath)) {
                    $r = Get-ScanResult -Path $logPath -MinAgeDays 30 -Recurse
                    $totalBytes = $r.Bytes; $totalFiles = $r.Files
                }
                $results.Add([PSCustomObject]@{
                    Module = 'IIS Logs'; Key = 'IISLogCleanup'
                    Files = $totalFiles; Size = $totalBytes; SizeText = if ($Script:IsAdmin) { Format-FileSize $totalBytes } else { '--' }
                    Type = 'Cleanup'; Status = if (-not $Script:IsAdmin) { 'Needs Admin' } elseif (-not (Test-Path "$env:SystemDrive\inetpub")) { 'Not Installed' } elseif ($totalBytes -gt 0) { 'Recoverable' } else { 'Clean' }
                })
            }
            'FreeSpaceWiper' {
                $freeGB = 0
                try {
                    $driveInfo = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
                    $freeGB = [math]::Round($driveInfo.Free / 1GB, 2)
                } catch {}
                $results.Add([PSCustomObject]@{
                    Module = 'Free Space Wipe'; Key = 'FreeSpaceWiper'
                    Files = 0; Size = [long]0; SizeText = "$freeGB GB free"
                    Type = 'Tool'; Status = if ($Script:IsAdmin) { 'Ready' } else { 'Needs Admin' }
                })
            }
            'RestorePointAnalysis' {
                $rpCount = 0
                if ($Script:IsAdmin) {
                    try {
                        $rps = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
                        if ($rps) { $rpCount = @($rps).Count }
                    } catch {}
                }
                $results.Add([PSCustomObject]@{
                    Module = 'Restore Points'; Key = 'RestorePointAnalysis'
                    Files = $rpCount; Size = [long]0; SizeText = "$rpCount points"
                    Type = 'Analysis'; Status = if ($Script:IsAdmin) { 'Ready' } else { 'Needs Admin' }
                })
            }
        }
        Play-RetroSound -Type 'ScanTick'
    }

    Play-RetroSound -Type 'ScanComplete'

    return $results
}

function Write-ScanTable {
    <#
    .SYNOPSIS
        Displays the pre-scan results in a formatted table with totals.
    #>
    param([System.Collections.Generic.List[PSCustomObject]]$ScanResults)

    $separator = [string]::new('=', 78)
    $rowLine   = [string]::new('-', 78)

    Write-Host ""
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "  SYSTEM SCAN RESULTS" -ForegroundColor White
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""

    # Table header
    Write-Host ("  " + 'MODULE'.PadRight(24) + 'RECLAIMABLE'.PadLeft(14) + 'FILES'.PadLeft(10) + '  ' + 'TYPE'.PadRight(14) + 'STATUS') -ForegroundColor White
    Write-Host "  $rowLine" -ForegroundColor DarkGray

    $totalRecoverable = [long]0
    $totalFiles = 0
    $cleanupCount = 0

    foreach ($row in $ScanResults) {
        # Color based on status
        $statusColor = switch ($row.Status) {
            'Recoverable' { 'Yellow' }
            'Clean'       { 'Green' }
            'Needs Admin' { 'DarkGray' }
            'Available'   { 'Cyan' }
            'Ready'       { 'Cyan' }
            default       { 'Gray' }
        }

        $sizeColor = if ($row.Size -ge 1GB) { 'Red' } elseif ($row.Size -ge 100MB) { 'Yellow' } elseif ($row.Size -gt 0) { 'White' } else { 'DarkGray' }

        # Print module name
        Write-Host ("  " + $row.Module.PadRight(24)) -ForegroundColor White -NoNewline
        # Print size (right-aligned in 14-char field)
        Write-Host ($row.SizeText.PadLeft(14)) -ForegroundColor $sizeColor -NoNewline
        # Print file count
        $filesText = if ($row.Type -eq 'Cleanup') { '{0:N0}' -f $row.Files } elseif ($row.Files -gt 0) { "$($row.Files)" } else { '--' }
        Write-Host ($filesText.PadLeft(10)) -ForegroundColor Gray -NoNewline
        Write-Host "  " -NoNewline
        # Print type
        Write-Host ($row.Type.PadRight(14)) -ForegroundColor DarkCyan -NoNewline
        # Print status
        Write-Host $row.Status -ForegroundColor $statusColor

        if ($row.Status -eq 'Recoverable') {
            $totalRecoverable += $row.Size
            $totalFiles += $row.Files
            $cleanupCount++
        }
    }

    # Totals row
    Write-Host "  $rowLine" -ForegroundColor DarkGray
    $totalColor = if ($totalRecoverable -ge 1GB) { 'Red' } elseif ($totalRecoverable -ge 100MB) { 'Yellow' } else { 'Green' }
    Write-Host ("  " + 'TOTAL RECOVERABLE'.PadRight(24)) -ForegroundColor White -NoNewline
    Write-Host ((Format-FileSize $totalRecoverable).PadLeft(14)) -ForegroundColor $totalColor -NoNewline
    Write-Host (('{0:N0}' -f $totalFiles).PadLeft(10)) -ForegroundColor Gray
    Write-Host ""
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""

    Write-Log "Pre-scan complete. Total recoverable: $(Format-FileSize $totalRecoverable) across $totalFiles files in $cleanupCount modules." -Level INFO -NoConsole

    return $totalRecoverable
}

# -----------------------------------------------------------------------------
# SECTION 8 -- MAIN EXECUTION
# -----------------------------------------------------------------------------

function Invoke-Main {
    Write-Banner
    Play-RetroSound -Type 'Welcome'
    if ($Sound) { Write-Host "    Sound    : Enabled (retro beeps)" -ForegroundColor Green }
    if ($RetroUI) { Write-Host "    UI Mode  : Retro Terminal" -ForegroundColor Green }

    Write-Log "Session started. Version=$Script:Version DryRun=$DryRun Admin=$Script:IsAdmin" -Level INFO -NoConsole
    Write-Log "Resources: CPU=$Script:CoresAllocated/$Script:CpuCores cores, RAM=$Script:AvailRAM_MB/$Script:TotalRAM_MB MB, Priority=$Script:ProcessPriority" -Level INFO -NoConsole

    # Determine which modules to run
    $modulesToRun = @()

    if ($Modules -and $Modules.Count -gt 0) {
        $modulesToRun = $Modules
        Write-Log "Modules selected via parameter: $($modulesToRun -join ', ')" -Level INFO
    } elseif ($NonInteractive) {
        $modulesToRun = @($Script:AllModules.Keys)
        Write-Log "Non-interactive mode: running all modules." -Level INFO
    } elseif ($RetroUI) {
        $selected = Show-RetroUI
        if ($selected.Count -eq 0) { return }
        $modulesToRun = $selected
    } else {
        $modulesToRun = Show-InteractiveMenu
        if (-not $modulesToRun -or $modulesToRun.Count -eq 0) {
            Write-Host ""
            Write-Host "  No modules selected. Exiting." -ForegroundColor Gray
            return
        }
    }

    # Apply skip list
    if ($SkipModules -and $SkipModules.Count -gt 0) {
        $modulesToRun = $modulesToRun | Where-Object { $_ -notin $SkipModules }
        Write-Log "Skipping modules: $($SkipModules -join ', ')" -Level INFO
    }

    # ── PHASE 1: PRE-SCAN ──
    Write-Host ""
    Write-Log "Scanning system for reclaimable space..." -Level INFO
    Write-Host ""

    $scanResults = Invoke-PreScan -ModuleList $modulesToRun
    $totalReclaimable = Write-ScanTable -ScanResults $scanResults

    # Ask user to proceed
    if (-not $DryRun -and -not $NonInteractive) {
        if (-not (Request-Confirmation "Proceed with cleanup? ($(Format-FileSize $totalReclaimable) recoverable)")) {
            Write-Log "User cancelled after scan." -Level SKIP
            Write-Host "  Cancelled. No changes were made." -ForegroundColor Gray
            return
        }
    }

    if ($DryRun) {
        Write-Host "  DRY-RUN: Showing detailed breakdown per module below." -ForegroundColor Yellow
        Write-Host ""
    }

    # ── PHASE 2: EXECUTE MODULES ──
    Write-Log "Running modules: $($modulesToRun -join ', ')" -Level INFO

    $dispatch = @{
        'TempFiles'             = { Invoke-TempFileCleanup }
        'WindowsUpdate'         = { Invoke-WindowsUpdateCleanup }
        'RecycleBin'            = { Invoke-RecycleBinCleanup }
        'StartupAnalysis'       = { Invoke-StartupAnalysis }
        'DiskCleanup'           = { Invoke-DiskCleanup }
        'ServiceAnalysis'       = { Invoke-ServiceAnalysis }
        'BrowserCache'          = { Invoke-BrowserCacheCleanup }
        'EventLogs'             = { Invoke-EventLogCleanup }
        'PrefetchCleanup'       = { Invoke-PrefetchCleanup }
        'DeliveryOptimization'  = { Invoke-DeliveryOptimizationCleanup }
        'WindowsOldCleanup'     = { Invoke-WindowsOldCleanup }
        'CrashDumps'            = { Invoke-CrashDumpCleanup }
        'InstallerCleanup'      = { Invoke-InstallerCleanup }
        'ShaderCache'           = { Invoke-ShaderCacheCleanup }
        'ThumbCacheCleanup'     = { Invoke-ThumbCacheCleanup }
        'ComponentStoreCleanup' = { Invoke-ComponentStoreCleanup }
        'DNSCacheFlush'         = { Invoke-DNSCacheFlush }
        'WindowsStoreCache'     = { Invoke-WindowsStoreCacheCleanup }
        'SystemHealthCheck'     = { Invoke-SystemHealthCheck }
        'NetworkAnalysis'       = { Invoke-NetworkAnalysis }
        'ErrorReporting'        = { Invoke-ErrorReportingCleanup }
        'WindowsLogFiles'       = { Invoke-WindowsLogFileCleanup }
        'DefenderCache'         = { Invoke-DefenderCacheCleanup }
        'SearchIndexCleanup'    = { Invoke-SearchIndexCleanup }
        'ShadowCopyCleanup'     = { Invoke-ShadowCopyCleanup }
        'DevToolCaches'         = { Invoke-DevToolCacheCleanup }
        'AppCacheCleanup'       = { Invoke-AppCacheCleanup }
        'FontCacheRebuild'      = { Invoke-FontCacheRebuild }
        'DotNetCleanup'         = { Invoke-DotNetCleanup }
        'LargeFileFinder'       = { Invoke-LargeFileFinder }
        'DuplicateFileFinder'   = { Invoke-DuplicateFileFinder }
        'ScheduledTaskReview'   = { Invoke-ScheduledTaskReview }
        'WindowsPrivacyCleanup' = { Invoke-WindowsPrivacyCleanup }
        'BrowserPrivacyCleanup' = { Invoke-BrowserPrivacyCleanup }
        'OfficeCleanup'         = { Invoke-OfficeCleanup }
        'CloudStorageCleanup'   = { Invoke-CloudStorageCleanup }
        'AdobeCleanup'          = { Invoke-AdobeCleanup }
        'JavaCleanup'           = { Invoke-JavaCleanup }
        'ChkdskFragments'       = { Invoke-ChkdskFragmentCleanup }
        'IISLogCleanup'         = { Invoke-IISLogCleanup }
        'FreeSpaceWiper'        = { Invoke-FreeSpaceWiper }
        'RestorePointAnalysis'  = { Invoke-RestorePointAnalysis }
    }

    $execTotal = $modulesToRun.Count
    $execIndex = 0

    foreach ($mod in $modulesToRun) {
        $execIndex++
        $modName = if ($Script:AllModules.Contains($mod)) { $Script:AllModules[$mod].Name } else { $mod }
        Write-ProgressBar -Current $execIndex -Total $execTotal -Activity $modName
        Play-RetroSound -Type 'ActionStart'

        # Release memory between modules to keep working set lean
        Invoke-MemoryRelief -ThresholdMB 512

        if ($dispatch.ContainsKey($mod)) {
            try {
                & $dispatch[$mod]
            } catch {
                Write-Log "FATAL ERROR in module '$mod': $($_.Exception.Message)" -Level ERROR
                Write-Log $_.ScriptStackTrace -Level ERROR -NoConsole
                $Script:TotalErrors++
            }
        } else {
            Write-Log "Unknown module: $mod" -Level WARNING
        }
    }

    # Final report
    if ($Script:TotalErrors -gt 0) {
        Play-RetroSound -Type 'Warning'
    } else {
        Play-RetroSound -Type 'Complete'
    }
    Write-SummaryReport
}

# Entry point
Invoke-Main
