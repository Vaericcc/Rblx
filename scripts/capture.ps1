# Capture the StoryDub UI tour and build a labelled contact sheet.
#
#   .\scripts\capture.ps1 -Name before     then   .\scripts\capture.ps1 -Name after
#
# 1. Start this script. It counts down 15 seconds.
# 2. Click into the Studio play window and press F8 within those 15 seconds.
#    The in-game tour counts down 10 s, then shows each screen for 5 s with a label.
# 3. The script grabs the screen every 5 s, 20 times, stitches a sheet, and copies
#    the newest Studio logs next to it. Output: screenshots\<Name>\sheet.png
param(
  [string]$Name = "run",
  [int]$Shots = 20,
  [int]$Interval = 5,
  [int]$Countdown = 15,
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

$root = Join-Path (Split-Path $PSScriptRoot -Parent) "screenshots"
$dir = Join-Path $root $Name
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Get-ChildItem $dir -Filter "shot_*.png" -ErrorAction SilentlyContinue | Remove-Item -Force

for ($i = $Countdown; $i -gt 0; $i--) {
  Write-Host ("Switch to Studio and press F8 ... capturing in {0}s" -f $i)
  Start-Sleep -Seconds 1
}

$bounds = Get-CaptureRect
Write-Host ("Capturing {0}x{1} at {2},{3}" -f $bounds.Width, $bounds.Height, $bounds.X, $bounds.Y)
$files = @()
for ($k = 1; $k -le $Shots; $k++) {
  $bounds = Get-CaptureRect
  $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $g.Dispose()
  $file = Join-Path $dir ("shot_{0:D2}.png" -f $k)
  $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $files += $file
  Write-Host ("captured {0}/{1}" -f $k, $Shots)
  if ($k -lt $Shots) { Start-Sleep -Seconds $Interval }
}

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
$sg.DrawString(("StoryDub tour: {0}   {1}" -f $Name, (Get-Date -Format "yyyy-MM-dd HH:mm")), $font, $white, $pad, $pad)
for ($i = 0; $i -lt $files.Count; $i++) {
  $img = [System.Drawing.Image]::FromFile($files[$i])
  $col = $i % $Columns; $row = [math]::Floor($i / $Columns)
  $x = $pad + $col * ($ThumbWidth + $pad)
  $y = 50 + $pad + $row * ($thumbH + $pad + 28)
  $sg.DrawImage($img, $x, $y, $ThumbWidth, $thumbH)
  $sg.DrawString(("#{0}" -f ($i + 1)), $small, $white, $x, $y + $thumbH + 4)
  $img.Dispose()
}
$sg.Dispose()
$sheetPath = Join-Path $dir "sheet.png"
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

# Studio logs (newest two)
$logDir = Join-Path $env:LOCALAPPDATA "Roblox\logs"
if (Test-Path $logDir) {
  Get-ChildItem $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 2 | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dir ("log_" + $_.Name)) -Force
  }
}
Write-Host ""
Write-Host "Done. Send this file:" $sheetPath
Write-Host "Logs copied next to it."
