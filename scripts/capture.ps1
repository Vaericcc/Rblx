# Capture the Dubble Take UI tour and build a labelled contact sheet.
#
#   .\scripts\capture.ps1 -Name before     then   .\scripts\capture.ps1 -Name after
#
# 1. Start this script. It waits for the tour to begin (up to -WaitSeconds).
# 2. Click into the Studio play window and press F8 (or type /tour).
# 3. The tour prints "TOUR: <step>" to Output for every screen. Studio writes
#    Output to its log file, so this script tails the newest log and takes one
#    shot per step, -Settle seconds after the step appears (so animations finish).
#    It stops on "TOUR: finished". Output: screenshots\<Name>\sheet.png, each
#    thumbnail labelled with its step, plus the Studio logs.
param(
  [string]$Name = "run",
  [double]$Settle = 1.8,
  [int]$WaitSeconds = 120,
  [int]$StepTimeout = 30,
  [int]$Columns = 4,
  [int]$ThumbWidth = 640
)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Windows display scaling: without this the screen is reported in scaled units
# and the capture only covers the top-left part. Also lets us find the Studio window.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Native {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[Native]::SetProcessDPIAware() | Out-Null

function Get-CaptureRect {
  # Prefer the Roblox Studio window; fall back to the whole primary screen.
  $studio = Get-Process -Name "RobloxStudioBeta" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($studio) {
    $r = New-Object Native+RECT
    if ([Native]::GetWindowRect($studio.MainWindowHandle, [ref]$r)) {
      $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
      if ($w -gt 200 -and $h -gt 200) {
        return [System.Drawing.Rectangle]::new($r.Left, $r.Top, $w, $h)
      }
    }
  }
  return [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
}

function Take-Shot([string]$path) {
  $bounds = Get-CaptureRect
  $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return $bounds
}

# --- Studio log tail -------------------------------------------------------
$logDir = Join-Path $env:LOCALAPPDATA "Roblox\logs"
if (-not (Test-Path $logDir)) { Write-Error "Studio log folder not found: $logDir"; exit 1 }
function Newest-Log {
  Get-ChildItem $logDir -Filter "*.log" | Where-Object { $_.Name -match "Studio" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
# A new log file appears when Play starts, so re-pick the newest file while waiting.
$log = Newest-Log
if (-not $log) { Write-Error "No Studio log found. Is Studio running?"; exit 1 }
# The directory listing's size for a file Studio is still writing lags behind the
# real end of the file, so measure through an open handle.
function True-Length([string]$path) {
  $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
  try { return $fs.Length } finally { $fs.Dispose() }
}
$offset = True-Length $log.FullName
$started = (Get-Date).ToUniversalTime()
$pending = New-Object System.Collections.Generic.Queue[string]

function Pump-Log {
  # Read new bytes from the newest Studio log and queue every "TOUR: <step>" line.
  $latest = Newest-Log
  if ($latest.FullName -ne $script:log.FullName) {
    # Switched to a different log (Play started a new one). Only read it from the
    # beginning if it was created after this script started; an older file holds
    # TOUR lines from previous runs, which must be skipped.
    $script:log = $latest
    $script:offset = if ($latest.CreationTime.ToUniversalTime() -gt $script:started) { 0 } else { True-Length $latest.FullName }
  }
  $fs = [System.IO.File]::Open($script:log.FullName, 'Open', 'Read', 'ReadWrite')
  try {
    if ($fs.Length -lt $script:offset) { $script:offset = 0 }
    $fs.Seek($script:offset, 'Begin') | Out-Null
    $buf = New-Object byte[] ($fs.Length - $script:offset)
    $n = $fs.Read($buf, 0, $buf.Length)
    $script:offset += $n
  } finally { $fs.Dispose() }
  if ($n -le 0) { return }
  $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
  foreach ($line in ($text -split "[\r\n]+")) {
    $m = [regex]::Match($line, 'TOUR: (.+)$')
    if (-not $m.Success) { continue }
    # Roblox log lines start with an ISO timestamp; drop lines from before this run.
    $ts = [regex]::Match($line, '^(\d{4}-\d\d-\d\dT[\d:.]+Z)')
    if ($ts.Success) {
      $when = [DateTime]::Parse($ts.Groups[1].Value, $null, 'AdjustToUniversal')
      if ($when -lt $script:started.AddSeconds(-2)) { continue }
    }
    $pending.Enqueue($m.Groups[1].Value.Trim())
  }
}

function Next-Step([int]$timeoutSec) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    Pump-Log
    if ($pending.Count -gt 0) { return $pending.Dequeue() }
    Start-Sleep -Milliseconds 200
  }
  return $null
}

$root = Join-Path (Split-Path $PSScriptRoot -Parent) "screenshots"
$dir = Join-Path $root $Name
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Get-ChildItem $dir -Filter "shot_*.png" -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Host ("Tailing {0}" -f $log.Name)
Write-Host ("Switch to Studio and press F8 (or type /tour). Waiting up to {0}s for the tour to start..." -f $WaitSeconds)
# Wait for THIS run's start marker; anything else is a leftover from an earlier tour.
$step = Next-Step $WaitSeconds
while ($null -ne $step -and $step -ne "countdown") { Write-Host ("ignoring stale '{0}'" -f $step); $step = Next-Step $WaitSeconds }
if ($null -eq $step) { Write-Error "Tour never started (no 'TOUR: countdown' line in the Studio log). Pull the latest code, then press F8 in the play window."; exit 1 }
Write-Host "Tour started."

$files = @(); $labels = @(); $bounds = $null
while ($null -ne $step) {
  if ($step -eq "finished") { break }
  if ($step -in @("countdown", "done")) { $step = Next-Step $StepTimeout; continue }
  Start-Sleep -Milliseconds ([int]($Settle * 1000))
  $file = Join-Path $dir ("shot_{0:D2}_{1}.png" -f ($files.Count + 1), ($step -replace '[^\w]+', '_'))
  $bounds = Take-Shot $file
  $files += $file; $labels += $step
  Write-Host ("captured #{0}  {1}" -f $files.Count, $step)
  $step = Next-Step $StepTimeout
}
if ($null -eq $step) { Write-Warning "Tour went quiet for ${StepTimeout}s; building the sheet from what was captured." }
if ($files.Count -eq 0) { Write-Error "Nothing captured."; exit 1 }

# Contact sheet
$thumbH = [int]($ThumbWidth * $bounds.Height / $bounds.Width)
$rows = [math]::Ceiling($files.Count / $Columns)
$pad = 12
$sheet = New-Object System.Drawing.Bitmap ($Columns * ($ThumbWidth + $pad) + $pad), ($rows * ($thumbH + $pad + 28) + $pad + 50)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.Clear([System.Drawing.Color]::FromArgb(24, 24, 32))
$font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$small = New-Object System.Drawing.Font("Segoe UI", 11)
$white = [System.Drawing.Brushes]::White
$sg.DrawString(("Dubble Take tour: {0}   {1}" -f $Name, (Get-Date -Format "yyyy-MM-dd HH:mm")), $font, $white, $pad, $pad)
for ($i = 0; $i -lt $files.Count; $i++) {
  $img = [System.Drawing.Image]::FromFile($files[$i])
  $col = $i % $Columns; $row = [math]::Floor($i / $Columns)
  $x = $pad + $col * ($ThumbWidth + $pad)
  $y = 50 + $pad + $row * ($thumbH + $pad + 28)
  $sg.DrawImage($img, $x, $y, $ThumbWidth, $thumbH)
  $sg.DrawString(("#{0}  {1}" -f ($i + 1), $labels[$i]), $small, $white, $x, $y + $thumbH + 4)
  $img.Dispose()
}
$sg.Dispose()
$sheetPath = Join-Path $dir "sheet.png"
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

# Studio logs (newest two)
Get-ChildItem $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 2 | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $dir ("log_" + $_.Name)) -Force
}
Write-Host ""
Write-Host "Done. Send this file:" $sheetPath
Write-Host "Logs copied next to it."
