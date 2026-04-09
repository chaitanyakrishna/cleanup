<#
.SYNOPSIS
    System Maintenance Tool - Retro GUI Launcher
.DESCRIPTION
    A Windows Forms GUI wrapper for SystemMaintenanceTool.ps1 styled with
    a retro CRT-terminal aesthetic. Provides point-and-click module selection,
    live progress, and an embedded log viewer.
.NOTES
    Version : 6.0.0
    Requires: Windows PowerShell 5.1+, SystemMaintenanceTool.ps1 in same directory
#>

#Requires -Version 5.1

param(
    [string]$ScriptPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Win32 P/Invoke for process pause/resume
Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class ProcessControl {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenThread(int access, bool inherit, uint threadId);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint SuspendThread(IntPtr hThread);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr hThread);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    const int THREAD_SUSPEND_RESUME = 0x0002;

    public static bool Suspend(Process p) {
        try {
            foreach (ProcessThread t in p.Threads) {
                IntPtr h = OpenThread(THREAD_SUSPEND_RESUME, false, (uint)t.Id);
                if (h != IntPtr.Zero) { SuspendThread(h); CloseHandle(h); }
            }
            return true;
        } catch { return false; }
    }

    public static bool Resume(Process p) {
        try {
            foreach (ProcessThread t in p.Threads) {
                IntPtr h = OpenThread(THREAD_SUSPEND_RESUME, false, (uint)t.Id);
                if (h != IntPtr.Zero) { ResumeThread(h); CloseHandle(h); }
            }
            return true;
        } catch { return false; }
    }
}
"@ -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

$retroColors = @{
    Background   = [System.Drawing.Color]::FromArgb(10, 10, 10)
    Panel        = [System.Drawing.Color]::FromArgb(20, 25, 20)
    TextGreen    = [System.Drawing.Color]::FromArgb(0, 255, 65)
    TextDimGreen = [System.Drawing.Color]::FromArgb(0, 180, 45)
    TextAmber    = [System.Drawing.Color]::FromArgb(255, 176, 0)
    TextRed      = [System.Drawing.Color]::FromArgb(255, 60, 60)
    TextCyan     = [System.Drawing.Color]::FromArgb(0, 220, 220)
    TextWhite    = [System.Drawing.Color]::FromArgb(200, 220, 200)
    Border       = [System.Drawing.Color]::FromArgb(0, 120, 30)
    Highlight    = [System.Drawing.Color]::FromArgb(0, 80, 20)
    ButtonBg     = [System.Drawing.Color]::FromArgb(0, 60, 15)
    ButtonHover  = [System.Drawing.Color]::FromArgb(0, 100, 25)
    ProgressBar  = [System.Drawing.Color]::FromArgb(0, 255, 65)
    ProgressBg   = [System.Drawing.Color]::FromArgb(30, 40, 30)
}

$retroFont      = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Regular)
$retroFontBold  = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$retroFontSmall = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Regular)
$retroFontTitle = New-Object System.Drawing.Font('Consolas', 16, [System.Drawing.FontStyle]::Bold)
$retroFontSub   = New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Regular)

# ---------------------------------------------------------------------------
# RESOURCE MANAGEMENT -- keep GUI responsive
# ---------------------------------------------------------------------------

# Set GUI process priority to Normal (not BelowNormal -- UI needs responsiveness)
try {
    $guiProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $guiProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
} catch { }

$script:cpuCores   = [Environment]::ProcessorCount
$script:totalRAM   = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1MB, 0)
$script:availRAM   = [math]::Round((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).FreePhysicalMemory / 1KB, 0)

# Resolve main script path (works for .ps1, .exe, and -noConsole exe)
if (-not $ScriptPath) {
    # Try $PSScriptRoot first (works for .ps1)
    $baseDir = $PSScriptRoot
    # Fallback: exe location via process path
    if (-not $baseDir -or $baseDir -eq '') {
        try { $baseDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {}
    }
    # Fallback: current directory
    if (-not $baseDir -or $baseDir -eq '') {
        $baseDir = $PWD.Path
    }
    # Search: same dir first, then parent dir (handles build/ subfolder), then PWD
    $searchDirs = @($baseDir, (Split-Path $baseDir -Parent), $PWD.Path) | Select-Object -Unique
    $ScriptPath = $null
    foreach ($dir in $searchDirs) {
        $candidate = Join-Path $dir 'SystemMaintenanceTool.ps1'
        if (Test-Path $candidate) { $ScriptPath = $candidate; break }
    }
}
if (-not $ScriptPath -or -not (Test-Path $ScriptPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Cannot find SystemMaintenanceTool.ps1`n`nSearched in:`n$($searchDirs -join "`n")`n`nPlace the GUI launcher in the same folder as the main script.",
        'System Maintenance Tool - Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

# ---------------------------------------------------------------------------
# MODULE DEFINITIONS (must match main script)
# ---------------------------------------------------------------------------

$moduleData = [ordered]@{
    # Basic
    'TempFiles'             = @{ Name = 'Temporary File Cleanup';       Category = 'Basic';    Risk = 'Low' }
    'WindowsUpdate'         = @{ Name = 'Windows Update Cache';         Category = 'Basic';    Risk = 'Low' }
    'RecycleBin'            = @{ Name = 'Recycle Bin Cleanup';          Category = 'Basic';    Risk = 'Low' }
    'BrowserCache'          = @{ Name = 'Browser Cache Cleanup';        Category = 'Basic';    Risk = 'Low' }
    'EventLogs'             = @{ Name = 'Old Event Log Cleanup';        Category = 'Basic';    Risk = 'Low' }
    # Advanced
    'PrefetchCleanup'       = @{ Name = 'Prefetch Cache Cleanup';       Category = 'Advanced'; Risk = 'Low' }
    'DeliveryOptimization'  = @{ Name = 'Delivery Optimization Cache';  Category = 'Advanced'; Risk = 'Low' }
    'WindowsOldCleanup'     = @{ Name = 'Old Windows Installation';     Category = 'Advanced'; Risk = 'Medium' }
    'CrashDumps'            = @{ Name = 'Crash Dump Cleanup';           Category = 'Advanced'; Risk = 'Low' }
    'InstallerCleanup'      = @{ Name = 'Installer Patch Cache';        Category = 'Advanced'; Risk = 'Medium' }
    'ShaderCache'           = @{ Name = 'GPU Shader Cache Cleanup';     Category = 'Advanced'; Risk = 'Low' }
    'ThumbCacheCleanup'     = @{ Name = 'Thumbnail Cache Cleanup';      Category = 'Advanced'; Risk = 'Low' }
    'ErrorReporting'        = @{ Name = 'Windows Error Reports';        Category = 'Advanced'; Risk = 'Low' }
    'WindowsLogFiles'       = @{ Name = 'Diagnostic Log Archives';      Category = 'Advanced'; Risk = 'Low' }
    'DefenderCache'         = @{ Name = 'Defender History Cache';        Category = 'Advanced'; Risk = 'Low' }
    'SearchIndexCleanup'    = @{ Name = 'Search Index Rebuild';          Category = 'Advanced'; Risk = 'Low' }
    'ShadowCopyCleanup'     = @{ Name = 'Volume Shadow Copies';         Category = 'Advanced'; Risk = 'Medium' }
    'DevToolCaches'         = @{ Name = 'Developer Tool Caches';        Category = 'Advanced'; Risk = 'Low' }
    'AppCacheCleanup'       = @{ Name = 'Application Cache Cleanup';    Category = 'Advanced'; Risk = 'Low' }
    'DotNetCleanup'         = @{ Name = '.NET Native Image Cache';      Category = 'Advanced'; Risk = 'Medium' }
    'OfficeCleanup'         = @{ Name = 'Office Temp & Cache Cleanup';  Category = 'Advanced'; Risk = 'Low' }
    'CloudStorageCleanup'   = @{ Name = 'Cloud Storage Cache Cleanup';  Category = 'Advanced'; Risk = 'Low' }
    'AdobeCleanup'          = @{ Name = 'Adobe Product Cache Cleanup';  Category = 'Advanced'; Risk = 'Low' }
    'JavaCleanup'           = @{ Name = 'Java Cache Cleanup';           Category = 'Advanced'; Risk = 'Low' }
    'ChkdskFragments'       = @{ Name = 'Chkdsk File Fragments';        Category = 'Advanced'; Risk = 'Low' }
    'IISLogCleanup'         = @{ Name = 'IIS Log File Cleanup';         Category = 'Advanced'; Risk = 'Low' }
    # Privacy
    'WindowsPrivacyCleanup' = @{ Name = 'Windows Privacy Cleanup';      Category = 'Privacy';  Risk = 'Low' }
    'BrowserPrivacyCleanup' = @{ Name = 'Browser Privacy Cleanup';      Category = 'Privacy';  Risk = 'Medium' }
    # Tools
    'DiskCleanup'           = @{ Name = 'Windows Disk Cleanup';         Category = 'Tools';    Risk = 'Low' }
    'ComponentStoreCleanup' = @{ Name = 'Component Store (WinSxS)';     Category = 'Tools';    Risk = 'Low' }
    'DNSCacheFlush'         = @{ Name = 'DNS Cache Flush';              Category = 'Tools';    Risk = 'Low' }
    'WindowsStoreCache'     = @{ Name = 'Windows Store Cache Reset';    Category = 'Tools';    Risk = 'Low' }
    'FontCacheRebuild'      = @{ Name = 'Font Cache Rebuild';           Category = 'Tools';    Risk = 'Low' }
    'FreeSpaceWiper'        = @{ Name = 'Free Space Secure Wipe';       Category = 'Tools';    Risk = 'Medium' }
    # Analysis
    'StartupAnalysis'       = @{ Name = 'Startup Program Analysis';     Category = 'Analysis'; Risk = 'None' }
    'ServiceAnalysis'       = @{ Name = 'Service Optimization Analysis';Category = 'Analysis'; Risk = 'None' }
    'SystemHealthCheck'     = @{ Name = 'System Health Report';         Category = 'Analysis'; Risk = 'None' }
    'NetworkAnalysis'       = @{ Name = 'Network Diagnostics';          Category = 'Analysis'; Risk = 'None' }
    'LargeFileFinder'       = @{ Name = 'Large File Finder (>500MB)';   Category = 'Analysis'; Risk = 'None' }
    'DuplicateFileFinder'   = @{ Name = 'Duplicate File Finder';        Category = 'Analysis'; Risk = 'None' }
    'ScheduledTaskReview'   = @{ Name = 'Scheduled Task Review';        Category = 'Analysis'; Risk = 'None' }
    'RestorePointAnalysis'  = @{ Name = 'Restore Point Analysis';       Category = 'Analysis'; Risk = 'None' }
}

# ---------------------------------------------------------------------------
# CREATE MAIN FORM
# ---------------------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = 'System Maintenance Tool v6.0.0'
$form.Size = New-Object System.Drawing.Size(1200, 750)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $retroColors.Background
$form.ForeColor = $retroColors.TextGreen
$form.Font = $retroFont
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.MinimumSize = New-Object System.Drawing.Size(1050, 700)
$form.Icon = [System.Drawing.SystemIcons]::Application

# ---------------------------------------------------------------------------
# TITLE PANEL
# ---------------------------------------------------------------------------

$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Location = New-Object System.Drawing.Point(0, 0)
$titlePanel.Size = New-Object System.Drawing.Size(900, 70)
$titlePanel.BackColor = $retroColors.Panel
$titlePanel.Anchor = 'Top,Left,Right'

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'SYSTEM MAINTENANCE TOOL'
$titleLabel.Font = $retroFontTitle
$titleLabel.ForeColor = $retroColors.TextGreen
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(20, 10)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = '[ Retro Terminal Interface ] v6.0.0  |  Auditable - Safe - Transparent'
$subtitleLabel.Font = $retroFontSmall
$subtitleLabel.ForeColor = $retroColors.TextDimGreen
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(20, 42)

$titlePanel.Controls.Add($titleLabel)
$titlePanel.Controls.Add($subtitleLabel)
$form.Controls.Add($titlePanel)

# ---------------------------------------------------------------------------
# MODULE SELECTION PANEL (TreeView with checkboxes)
# ---------------------------------------------------------------------------

$moduleGroupBox = New-Object System.Windows.Forms.GroupBox
$moduleGroupBox.Text = ' Select Modules '
$moduleGroupBox.Font = $retroFontBold
$moduleGroupBox.ForeColor = $retroColors.TextCyan
$moduleGroupBox.BackColor = $retroColors.Background
$moduleGroupBox.Location = New-Object System.Drawing.Point(10, 78)
$moduleGroupBox.Size = New-Object System.Drawing.Size(310, 470)
$moduleGroupBox.Anchor = 'Top,Left,Bottom'

$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Location = New-Object System.Drawing.Point(10, 22)
$treeView.Size = New-Object System.Drawing.Size(290, 438)
$treeView.Anchor = 'Top,Left,Right,Bottom'
$treeView.CheckBoxes = $true
$treeView.BackColor = $retroColors.Panel
$treeView.ForeColor = $retroColors.TextGreen
$treeView.Font = $retroFont
$treeView.BorderStyle = 'FixedSingle'
$treeView.FullRowSelect = $true
$treeView.ShowLines = $true
$treeView.ShowPlusMinus = $true
$treeView.ShowRootLines = $true
$treeView.LineColor = $retroColors.Border

# Populate tree with categories
$categories = @('Basic','Advanced','Privacy','Tools','Analysis')
$categoryNodes = @{}

foreach ($cat in $categories) {
    $catNode = New-Object System.Windows.Forms.TreeNode
    $catNode.Text = "$($cat.ToUpper()) MODULES"
    $catNode.ForeColor = $retroColors.TextAmber
    $catNode.Tag = "CATEGORY:$cat"
    $catNode.Checked = $true
    $categoryNodes[$cat] = $catNode
    $treeView.Nodes.Add($catNode) | Out-Null
}

foreach ($key in $moduleData.Keys) {
    $mod = $moduleData[$key]
    $node = New-Object System.Windows.Forms.TreeNode
    $riskColor = switch ($mod.Risk) {
        'Low'    { $retroColors.TextGreen }
        'Medium' { $retroColors.TextAmber }
        'None'   { $retroColors.TextDimGreen }
        default  { $retroColors.TextGreen }
    }
    $node.Text = "$($mod.Name)  [$($mod.Risk)]"
    $node.ForeColor = $riskColor
    $node.Tag = $key
    $node.Checked = $true
    if ($categoryNodes.ContainsKey($mod.Category)) {
        $categoryNodes[$mod.Category].Nodes.Add($node) | Out-Null
    }
}

# Handle parent-child checkbox sync
$treeView.Add_AfterCheck({
    param($sender, $e)
    $node = $e.Node
    
    # If category node, propagate to children
    if ($node.Tag -and $node.Tag.ToString().StartsWith('CATEGORY:')) {
        foreach ($child in $node.Nodes) {
            $child.Checked = $node.Checked
        }
    }
})

# Expand all nodes
foreach ($catNode in $treeView.Nodes) { $catNode.Expand() }

$moduleGroupBox.Controls.Add($treeView)
$form.Controls.Add($moduleGroupBox)

# ---------------------------------------------------------------------------
# QUICK SELECT BUTTONS
# ---------------------------------------------------------------------------

$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = 'Select All'
$selectAllBtn.Location = New-Object System.Drawing.Point(10, 552)
$selectAllBtn.Size = New-Object System.Drawing.Size(100, 28)
$selectAllBtn.FlatStyle = 'Flat'
$selectAllBtn.BackColor = $retroColors.ButtonBg
$selectAllBtn.ForeColor = $retroColors.TextGreen
$selectAllBtn.Font = $retroFontSmall
$selectAllBtn.FlatAppearance.BorderColor = $retroColors.Border
$selectAllBtn.Anchor = 'Left,Bottom'
$selectAllBtn.Add_Click({
    foreach ($catNode in $treeView.Nodes) {
        $catNode.Checked = $true
        foreach ($child in $catNode.Nodes) { $child.Checked = $true }
    }
})

$selectNoneBtn = New-Object System.Windows.Forms.Button
$selectNoneBtn.Text = 'Select None'
$selectNoneBtn.Location = New-Object System.Drawing.Point(115, 552)
$selectNoneBtn.Size = New-Object System.Drawing.Size(100, 28)
$selectNoneBtn.FlatStyle = 'Flat'
$selectNoneBtn.BackColor = $retroColors.ButtonBg
$selectNoneBtn.ForeColor = $retroColors.TextAmber
$selectNoneBtn.Font = $retroFontSmall
$selectNoneBtn.FlatAppearance.BorderColor = $retroColors.Border
$selectNoneBtn.Anchor = 'Left,Bottom'
$selectNoneBtn.Add_Click({
    foreach ($catNode in $treeView.Nodes) {
        $catNode.Checked = $false
        foreach ($child in $catNode.Nodes) { $child.Checked = $false }
    }
})

$selectBasicBtn = New-Object System.Windows.Forms.Button
$selectBasicBtn.Text = 'Basic Only'
$selectBasicBtn.Location = New-Object System.Drawing.Point(220, 552)
$selectBasicBtn.Size = New-Object System.Drawing.Size(100, 28)
$selectBasicBtn.FlatStyle = 'Flat'
$selectBasicBtn.BackColor = $retroColors.ButtonBg
$selectBasicBtn.ForeColor = $retroColors.TextCyan
$selectBasicBtn.Font = $retroFontSmall
$selectBasicBtn.FlatAppearance.BorderColor = $retroColors.Border
$selectBasicBtn.Anchor = 'Left,Bottom'
$selectBasicBtn.Add_Click({
    foreach ($catNode in $treeView.Nodes) {
        $isBasic = $catNode.Tag -eq 'CATEGORY:Basic'
        $catNode.Checked = $isBasic
        foreach ($child in $catNode.Nodes) { $child.Checked = $isBasic }
    }
})

$form.Controls.Add($selectAllBtn)
$form.Controls.Add($selectNoneBtn)
$form.Controls.Add($selectBasicBtn)

# ---------------------------------------------------------------------------
# OPTIONS PANEL
# ---------------------------------------------------------------------------

$optionsGroupBox = New-Object System.Windows.Forms.GroupBox
$optionsGroupBox.Text = ' Options '
$optionsGroupBox.Font = $retroFontBold
$optionsGroupBox.ForeColor = $retroColors.TextCyan
$optionsGroupBox.BackColor = $retroColors.Background
$optionsGroupBox.Location = New-Object System.Drawing.Point(920, 78)
$optionsGroupBox.Size = New-Object System.Drawing.Size(260, 110)
$optionsGroupBox.Anchor = 'Top,Right'

$dryRunCheckbox = New-Object System.Windows.Forms.CheckBox
$dryRunCheckbox.Text = 'Dry Run (preview only)'
$dryRunCheckbox.Checked = $true
$dryRunCheckbox.ForeColor = $retroColors.TextAmber
$dryRunCheckbox.Font = $retroFont
$dryRunCheckbox.Location = New-Object System.Drawing.Point(15, 25)
$dryRunCheckbox.AutoSize = $true

$soundCheckbox = New-Object System.Windows.Forms.CheckBox
$soundCheckbox.Text = 'Sound Effects (beeps)'
$soundCheckbox.Checked = $false
$soundCheckbox.ForeColor = $retroColors.TextGreen
$soundCheckbox.Font = $retroFont
$soundCheckbox.Location = New-Object System.Drawing.Point(15, 52)
$soundCheckbox.AutoSize = $true

$nonInteractiveCheckbox = New-Object System.Windows.Forms.CheckBox
$nonInteractiveCheckbox.Text = 'Non-Interactive (auto)'
$nonInteractiveCheckbox.Checked = $false
$nonInteractiveCheckbox.ForeColor = $retroColors.TextGreen
$nonInteractiveCheckbox.Font = $retroFont
$nonInteractiveCheckbox.Location = New-Object System.Drawing.Point(15, 79)
$nonInteractiveCheckbox.AutoSize = $true

$optionsGroupBox.Controls.Add($dryRunCheckbox)
$optionsGroupBox.Controls.Add($soundCheckbox)
$optionsGroupBox.Controls.Add($nonInteractiveCheckbox)
$form.Controls.Add($optionsGroupBox)

# ---------------------------------------------------------------------------
# SYSTEM INFO PANEL
# ---------------------------------------------------------------------------

$infoGroupBox = New-Object System.Windows.Forms.GroupBox
$infoGroupBox.Text = ' System Info '
$infoGroupBox.Font = $retroFontBold
$infoGroupBox.ForeColor = $retroColors.TextCyan
$infoGroupBox.BackColor = $retroColors.Background
$infoGroupBox.Location = New-Object System.Drawing.Point(920, 195)
$infoGroupBox.Size = New-Object System.Drawing.Size(260, 130)
$infoGroupBox.Anchor = 'Top,Right'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
$osName = if ($os) { $os.Caption -replace 'Microsoft ', '' } else { 'Unknown' }
$ramGB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) } else { '?' }
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
$diskFreeGB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { '?' }
$diskTotalGB = if ($disk) { [math]::Round($disk.Size / 1GB, 1) } else { '?' }

$sysInfoText = @"
PC   : $($env:COMPUTERNAME)
User : $($env:USERNAME) $(if ($isAdmin) { '[ADMIN]' } else { '[Std]' })
OS   : $osName
RAM  : $ramGB GB total
Disk : C: $diskFreeGB / $diskTotalGB GB free
CPU  : $($script:cpuCores) cores
"@

$sysInfoLabel = New-Object System.Windows.Forms.Label
$sysInfoLabel.Text = $sysInfoText
$sysInfoLabel.Font = $retroFontSmall
$sysInfoLabel.ForeColor = $retroColors.TextDimGreen
$sysInfoLabel.Location = New-Object System.Drawing.Point(15, 22)
$sysInfoLabel.AutoSize = $true

$infoGroupBox.Controls.Add($sysInfoLabel)
$form.Controls.Add($infoGroupBox)

# ---------------------------------------------------------------------------
# LEGEND / HELP PANEL (right side, below system info)
# ---------------------------------------------------------------------------

$legendGroupBox = New-Object System.Windows.Forms.GroupBox
$legendGroupBox.Text = ' Log Legend '
$legendGroupBox.Font = $retroFontBold
$legendGroupBox.ForeColor = $retroColors.TextCyan
$legendGroupBox.BackColor = $retroColors.Background
$legendGroupBox.Location = New-Object System.Drawing.Point(920, 335)
$legendGroupBox.Size = New-Object System.Drawing.Size(260, 213)
$legendGroupBox.Anchor = 'Top,Right,Bottom'

$legendLabel = New-Object System.Windows.Forms.Label
$legendLabel.Font = $retroFontSmall
$legendLabel.ForeColor = $retroColors.TextDimGreen
$legendLabel.Location = New-Object System.Drawing.Point(15, 22)
$legendLabel.AutoSize = $true
$legendLabel.Text = @"
[INFO]    = Informational message
[ACTION]  = Performing cleanup
[SUCCESS] = Operation completed
[WARNING] = Non-critical issue
[ERROR]   = Operation failed
[SKIP]    = Module skipped
[DETAIL]  = Verbose detail

Tip: Use DRY RUN to preview
changes before execution.
"@

$legendGroupBox.Controls.Add($legendLabel)
$form.Controls.Add($legendGroupBox)

# ---------------------------------------------------------------------------
# LOG OUTPUT PANEL -- CENTER (main focal area)
# ---------------------------------------------------------------------------

$logGroupBox = New-Object System.Windows.Forms.GroupBox
$logGroupBox.Text = ' Output Log '
$logGroupBox.Font = $retroFontBold
$logGroupBox.ForeColor = $retroColors.TextCyan
$logGroupBox.BackColor = $retroColors.Background
$logGroupBox.Location = New-Object System.Drawing.Point(330, 78)
$logGroupBox.Size = New-Object System.Drawing.Size(580, 470)
$logGroupBox.Anchor = 'Top,Left,Right,Bottom'

$logTextBox = New-Object System.Windows.Forms.RichTextBox
$logTextBox.Location = New-Object System.Drawing.Point(10, 22)
$logTextBox.Size = New-Object System.Drawing.Size(560, 438)
$logTextBox.Anchor = 'Top,Left,Right,Bottom'
$logTextBox.BackColor = $retroColors.Panel
$logTextBox.ForeColor = $retroColors.TextGreen
$logTextBox.Font = $retroFontSmall
$logTextBox.ReadOnly = $true
$logTextBox.BorderStyle = 'None'
$logTextBox.ScrollBars = 'Vertical'
$logTextBox.WordWrap = $true

function Write-GUILog {
    param([string]$Message, [System.Drawing.Color]$Color)
    if (-not $Color) { $Color = $retroColors.TextGreen }
    $logTextBox.SelectionStart = $logTextBox.TextLength
    $logTextBox.SelectionLength = 0
    $logTextBox.SelectionColor = $Color
    $logTextBox.AppendText("$Message`r`n")
    $logTextBox.ScrollToCaret()
}

$logGroupBox.Controls.Add($logTextBox)
$form.Controls.Add($logGroupBox)

# ---------------------------------------------------------------------------
# PROGRESS BAR
# ---------------------------------------------------------------------------

$progressPanel = New-Object System.Windows.Forms.Panel
$progressPanel.Location = New-Object System.Drawing.Point(330, 552)
$progressPanel.Size = New-Object System.Drawing.Size(580, 28)
$progressPanel.BackColor = $retroColors.Background
$progressPanel.Anchor = 'Left,Right,Bottom'

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(0, 0)
$progressBar.Size = New-Object System.Drawing.Size(580, 28)
$progressBar.Anchor = 'Left,Right'
$progressBar.Style = 'Continuous'
$progressBar.BackColor = $retroColors.ProgressBg
$progressBar.ForeColor = $retroColors.ProgressBar
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0

$progressPanel.Controls.Add($progressBar)
$form.Controls.Add($progressPanel)

# ---------------------------------------------------------------------------
# ACTION BUTTONS
# ---------------------------------------------------------------------------

$runBtn = New-Object System.Windows.Forms.Button
$runBtn.Text = '>>> RUN <<<'
$runBtn.Location = New-Object System.Drawing.Point(10, 585)
$runBtn.Size = New-Object System.Drawing.Size(310, 50)
$runBtn.Anchor = 'Left,Bottom'
$runBtn.FlatStyle = 'Flat'
$runBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 80, 20)
$runBtn.ForeColor = $retroColors.TextGreen
$runBtn.Font = New-Object System.Drawing.Font('Consolas', 14, [System.Drawing.FontStyle]::Bold)
$runBtn.FlatAppearance.BorderColor = $retroColors.TextGreen
$runBtn.FlatAppearance.BorderSize = 2

# Pause / Resume button
$script:isPaused = $false
$pauseBtn = New-Object System.Windows.Forms.Button
$pauseBtn.Text = 'PAUSE'
$pauseBtn.Location = New-Object System.Drawing.Point(330, 585)
$pauseBtn.Size = New-Object System.Drawing.Size(140, 50)
$pauseBtn.Anchor = 'Left,Bottom'
$pauseBtn.FlatStyle = 'Flat'
$pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 0)
$pauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 0)
$pauseBtn.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$pauseBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 200, 0)
$pauseBtn.FlatAppearance.BorderSize = 2
$pauseBtn.Enabled = $false

$cancelBtn = New-Object System.Windows.Forms.Button
$cancelBtn.Text = 'STOP'
$cancelBtn.Location = New-Object System.Drawing.Point(475, 585)
$cancelBtn.Size = New-Object System.Drawing.Size(140, 50)
$cancelBtn.Anchor = 'Left,Bottom'
$cancelBtn.FlatStyle = 'Flat'
$cancelBtn.BackColor = [System.Drawing.Color]::FromArgb(120, 0, 0)
$cancelBtn.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
$cancelBtn.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$cancelBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 60, 60)
$cancelBtn.FlatAppearance.BorderSize = 2
$cancelBtn.Enabled = $false

$openLogBtn = New-Object System.Windows.Forms.Button
$openLogBtn.Text = 'Open Log'
$openLogBtn.Location = New-Object System.Drawing.Point(920, 585)
$openLogBtn.Size = New-Object System.Drawing.Size(125, 50)
$openLogBtn.Anchor = 'Right,Bottom'
$openLogBtn.FlatStyle = 'Flat'
$openLogBtn.BackColor = $retroColors.ButtonBg
$openLogBtn.ForeColor = $retroColors.TextCyan
$openLogBtn.Font = $retroFontBold
$openLogBtn.FlatAppearance.BorderColor = $retroColors.Border
$openLogBtn.Enabled = $false

$openFolderBtn = New-Object System.Windows.Forms.Button
$openFolderBtn.Text = 'Logs Dir'
$openFolderBtn.Location = New-Object System.Drawing.Point(1050, 585)
$openFolderBtn.Size = New-Object System.Drawing.Size(125, 50)
$openFolderBtn.Anchor = 'Right,Bottom'
$openFolderBtn.FlatStyle = 'Flat'
$openFolderBtn.BackColor = $retroColors.ButtonBg
$openFolderBtn.ForeColor = $retroColors.TextDimGreen
$openFolderBtn.Font = $retroFontBold
$openFolderBtn.FlatAppearance.BorderColor = $retroColors.Border
$openFolderBtn.Add_Click({
    $logDir = Join-Path (Split-Path $ScriptPath) 'logs'
    if (Test-Path $logDir) {
        Start-Process explorer.exe -ArgumentList $logDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("Logs directory not found: $logDir", 'Info')
    }
})

$form.Controls.Add($runBtn)
$form.Controls.Add($pauseBtn)
$form.Controls.Add($cancelBtn)
$form.Controls.Add($openLogBtn)
$form.Controls.Add($openFolderBtn)

# ---------------------------------------------------------------------------
# STATUS BAR
# ---------------------------------------------------------------------------

$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Text = '  Ready. Select modules and click RUN MAINTENANCE to begin.'
$statusBar.Location = New-Object System.Drawing.Point(0, 618)
$statusBar.Size = New-Object System.Drawing.Size(900, 25)
$statusBar.Anchor = 'Left,Right,Bottom'
$statusBar.BackColor = $retroColors.Panel
$statusBar.ForeColor = $retroColors.TextDimGreen
$statusBar.Font = $retroFontSmall
$statusBar.TextAlign = 'MiddleLeft'
$form.Controls.Add($statusBar)

# ---------------------------------------------------------------------------
# RUN BUTTON HANDLER
# ---------------------------------------------------------------------------

$script:currentProcess = $null
$script:lastLogFile = $null

$runBtn.Add_Click({
    # Collect selected modules
    $selectedModules = @()
    foreach ($catNode in $treeView.Nodes) {
        foreach ($modNode in $catNode.Nodes) {
            if ($modNode.Checked -and $modNode.Tag) {
                $selectedModules += $modNode.Tag.ToString()
            }
        }
    }
    
    if ($selectedModules.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No modules selected. Please select at least one module.",
            'System Maintenance Tool',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    # Build command
    $moduleList = $selectedModules -join ','
    $args = @('-ExecutionPolicy', 'Bypass', '-Command')
    $cmd = "& '$ScriptPath' -Modules $moduleList -NonInteractive"
    if ($dryRunCheckbox.Checked) { $cmd += ' -DryRun' }
    if ($soundCheckbox.Checked) { $cmd += ' -Sound' }
    
    # Update UI state
    $runBtn.Enabled = $false
    $runBtn.Text = 'RUNNING...'
    $runBtn.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 0)
    $cancelBtn.Enabled = $true
    $pauseBtn.Enabled = $true
    $script:isPaused = $false
    $pauseBtn.Text = 'PAUSE'
    $pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 0)
    $treeView.Enabled = $false
    $logTextBox.Clear()
    $progressBar.Value = 0
    $statusBar.Text = "  Running $($selectedModules.Count) modules..."
    $statusBar.ForeColor = $retroColors.TextAmber
    $form.Refresh()
    
    Write-GUILog "Starting maintenance with $($selectedModules.Count) modules..." $retroColors.TextCyan
    Write-GUILog "Mode: $(if ($dryRunCheckbox.Checked) { 'DRY-RUN (preview only)' } else { 'LIVE EXECUTION' })" $retroColors.TextAmber
    Write-GUILog ('=' * 60) $retroColors.TextDimGreen
    
    # Play welcome sound
    if ($soundCheckbox.Checked) {
        try { [Console]::Beep(523, 100); Start-Sleep -Milliseconds 50; [Console]::Beep(659, 100); Start-Sleep -Milliseconds 50; [Console]::Beep(784, 200) } catch {}
    }
    
    # Run the script
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -Command `"$cmd`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    
    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $script:currentProcess = $process

        $process.Start() | Out-Null

        # Set child process to BelowNormal priority so it never starves the GUI
        try {
            $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
        } catch { }

        # On 4+ core systems, pin child to cores 0..(N-2), leaving last core for GUI
        try {
            if ($script:cpuCores -ge 4) {
                $affinityMask = [IntPtr]((1 -shl ($script:cpuCores - 1)) - 1)
                $process.ProcessorAffinity = $affinityMask
            }
        } catch { }

        # Thread-safe queue: async OutputDataReceived pushes lines here,
        # UI timer drains them -- NEVER blocks the UI thread.
        $script:outputQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $script:processExited = $false

        # Wire up async output/error events (run on .NET threadpool, never on UI thread)
        $process.Add_OutputDataReceived({
            param($sender, $e)
            if ($null -ne $e.Data) {
                $script:outputQueue.Enqueue($e.Data)
            }
        })
        $process.Add_ErrorDataReceived({
            param($sender, $e)
            if ($null -ne $e.Data -and $e.Data.Trim()) {
                $script:outputQueue.Enqueue("STDERR: $($e.Data)")
            }
        })
        $process.Add_Exited({
            $script:processExited = $true
        })
        $process.EnableRaisingEvents = $true

        # Start async reads -- data flows into the queue without touching UI thread
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()

        # UI timer: drains the queue and updates the RichTextBox (never reads pipe directly)
        $readTimer = New-Object System.Windows.Forms.Timer
        $readTimer.Interval = 80

        $readTimer.Add_Tick({
            # Drain up to 20 lines per tick from the queue
            $linesThisTick = 0
            $maxLinesPerTick = 20
            $line = $null

            while ($linesThisTick -lt $maxLinesPerTick -and $script:outputQueue.TryDequeue([ref]$line)) {
                $script:guiLineCount++

                # Determine color based on content
                $lineColor = $retroColors.TextGreen
                if ($line -match '\[ERROR\]')       { $lineColor = $retroColors.TextRed }
                elseif ($line -match 'STDERR:')      { $lineColor = $retroColors.TextRed }
                elseif ($line -match '\[WARNING\]')  { $lineColor = $retroColors.TextAmber }
                elseif ($line -match '\[SUCCESS\]')  { $lineColor = $retroColors.TextGreen }
                elseif ($line -match '\[ACTION\]')   { $lineColor = $retroColors.TextAmber }
                elseif ($line -match '\[INFO\]')     { $lineColor = $retroColors.TextCyan }
                elseif ($line -match '\[SKIP\]')     { $lineColor = $retroColors.TextDimGreen }
                elseif ($line -match '\[DETAIL\]')   { $lineColor = $retroColors.TextDimGreen }
                elseif ($line -match '={5,}|~{5,}')  { $lineColor = $retroColors.TextDimGreen }

                $cleanLine = $line -replace '\r',''
                # Filter out CLI progress bar ASCII art (GUI has its own progress bar)
                if ($cleanLine -match '^\s*\[#{1,}' -or $cleanLine -match '^\s*Progress:.*\[') { $linesThisTick++; continue }
                if ($cleanLine.Trim().Length -gt 0) {
                    Write-GUILog $cleanLine $lineColor
                }

                $linesThisTick++

                # Update progress (approximate)
                $pct = [Math]::Min(95, [Math]::Floor(($script:guiLineCount / [Math]::Max(1, $script:guiExpectedLines)) * 100))
                $progressBar.Value = $pct

                # Extract log file path
                if ($line -match 'Log File\s*:\s*(.+)$') {
                    $script:lastLogFile = $Matches[1].Trim()
                }
            }

            # Check if child process has finished AND queue is empty
            if ($script:processExited -and $script:outputQueue.IsEmpty) {
                $this.Stop()
                $this.Dispose()

                $exitCode = 1
                try { $exitCode = $script:currentProcess.ExitCode } catch {}
                $progressBar.Value = 100

                # Show peak memory of child process
                try {
                    $childPeakMB = [math]::Round($script:currentProcess.PeakWorkingSet64 / 1MB, 1)
                    Write-GUILog "  Resources: Peak RAM ${childPeakMB} MB | $($script:cpuCores) CPU cores" $retroColors.TextDimGreen
                } catch { }

                if ($exitCode -eq 0) {
                    Write-GUILog '' $retroColors.TextGreen
                    Write-GUILog ('=' * 60) $retroColors.TextGreen
                    Write-GUILog 'MAINTENANCE COMPLETE' $retroColors.TextGreen
                    $statusBar.Text = '  Completed successfully!'
                    $statusBar.ForeColor = $retroColors.TextGreen
                    if ($soundCheckbox.Checked) {
                        try {
                            @(@(523,80),@(523,80),@(523,80),@(523,300),@(415,300),@(466,300),@(523,200),@(466,80),@(523,400)) | ForEach-Object {
                                [Console]::Beep($_[0], $_[1]); Start-Sleep -Milliseconds 30
                            }
                        } catch {}
                    }
                } else {
                    Write-GUILog "Process exited with code: $exitCode" $retroColors.TextRed
                    $statusBar.Text = "  Completed with errors (exit code: $exitCode)"
                    $statusBar.ForeColor = $retroColors.TextRed
                    if ($soundCheckbox.Checked) {
                        try { [Console]::Beep(200, 300); Start-Sleep -Milliseconds 50; [Console]::Beep(150, 300) } catch {}
                    }
                }

                # Restore UI state
                $runBtn.Enabled = $true
                $runBtn.Text = '>>> RUN <<<'
                $runBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 80, 20)
                $cancelBtn.Enabled = $false
                $pauseBtn.Enabled = $false
                $pauseBtn.Text = 'PAUSE'
                $script:isPaused = $false
                $treeView.Enabled = $true
                try { $script:currentProcess.Dispose() } catch {}
                $script:currentProcess = $null

                if ($script:lastLogFile -and (Test-Path $script:lastLogFile)) {
                    $openLogBtn.Enabled = $true
                }
            }
        })

        # Initialize counters and start the timer
        $script:guiLineCount    = 0
        $script:guiExpectedLines = $selectedModules.Count * 15
        $readTimer.Start()

    } catch {
        Write-GUILog "Error launching script: $($_.Exception.Message)" $retroColors.TextRed
        $statusBar.Text = "  Error: $($_.Exception.Message)"
        $statusBar.ForeColor = $retroColors.TextRed
        # Restore UI on error
        $runBtn.Enabled = $true
        $runBtn.Text = '>>> RUN <<<'
        $runBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 80, 20)
        $cancelBtn.Enabled = $false
        $pauseBtn.Enabled = $false
        $pauseBtn.Text = 'PAUSE'
        $script:isPaused = $false
        $treeView.Enabled = $true
        $script:currentProcess = $null
    }
})

# Cancel button handler
$cancelBtn.Add_Click({
    if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
        try {
            # Resume first if paused (Kill on suspended process can hang)
            if ($script:isPaused) {
                try { [ProcessControl]::Resume($script:currentProcess) } catch {}
            }
            # Cancel async reads before killing to avoid pipe errors
            try { $script:currentProcess.CancelOutputRead() } catch {}
            try { $script:currentProcess.CancelErrorRead() } catch {}
            $script:currentProcess.Kill()
            $script:processExited = $true
        } catch {}
        Write-GUILog 'Process stopped by user.' $retroColors.TextAmber
        $statusBar.Text = '  Stopped by user.'
        $statusBar.ForeColor = $retroColors.TextAmber
        # Restore UI state
        $runBtn.Enabled = $true
        $runBtn.Text = '>>> RUN <<<'
        $runBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 80, 20)
        $cancelBtn.Enabled = $false
        $pauseBtn.Enabled = $false
        $pauseBtn.Text = 'PAUSE'
        $pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 0)
        $pauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 0)
        $script:isPaused = $false
        $treeView.Enabled = $true
        try { $script:currentProcess.Dispose() } catch {}
        $script:currentProcess = $null
    }
})

# Pause / Resume button handler
$pauseBtn.Add_Click({
    if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
        if (-not $script:isPaused) {
            # PAUSE
            $ok = [ProcessControl]::Suspend($script:currentProcess)
            if ($ok) {
                $script:isPaused = $true
                $pauseBtn.Text = 'RESUME'
                $pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 100, 100)
                $pauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 255)
                $pauseBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 255, 255)
                Write-GUILog '[PAUSED] Process suspended by user.' $retroColors.TextAmber
                $statusBar.Text = '  PAUSED - Click RESUME to continue'
                $statusBar.ForeColor = $retroColors.TextAmber
            } else {
                Write-GUILog '[WARNING] Could not pause process.' $retroColors.TextRed
            }
        } else {
            # RESUME
            $ok = [ProcessControl]::Resume($script:currentProcess)
            if ($ok) {
                $script:isPaused = $false
                $pauseBtn.Text = 'PAUSE'
                $pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 0)
                $pauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 0)
                $pauseBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 200, 0)
                Write-GUILog '[RESUMED] Process resumed.' $retroColors.TextCyan
                $statusBar.Text = '  Running...'
                $statusBar.ForeColor = $retroColors.TextAmber
            } else {
                Write-GUILog '[WARNING] Could not resume process.' $retroColors.TextRed
            }
        }
    }
})
$openLogBtn.Add_Click({
    if ($script:lastLogFile -and (Test-Path $script:lastLogFile)) {
        Start-Process notepad.exe -ArgumentList $script:lastLogFile
    }
})

# ---------------------------------------------------------------------------
# CRT SCANLINE EFFECT (disabled for performance -- causes "Not Responding" on repaints)
# ---------------------------------------------------------------------------
# Removed: The scanline Paint handler drew hundreds of rectangles per repaint,
# starving the UI thread. The dark background already provides the retro look.

# ---------------------------------------------------------------------------
# LAUNCH
# ---------------------------------------------------------------------------

Write-GUILog '  System Maintenance Tool - Retro GUI' $retroColors.TextCyan
Write-GUILog '  Select modules, configure options, and click RUN.' $retroColors.TextDimGreen
Write-GUILog '' $retroColors.TextGreen

[System.Windows.Forms.Application]::EnableVisualStyles()
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

# Cleanup
$form.Dispose()
