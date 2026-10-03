# Put two tour sheets side by side: .\scripts\compare.ps1 -Before before -After after
param([string]$Before = "before", [string]$After = "after")
Add-Type -AssemblyName System.Drawing
$root = Join-Path (Split-Path $PSScriptRoot -Parent) "screenshots"
$a = [System.Drawing.Image]::FromFile((Join-Path $root "$Before\sheet.png"))
$b = [System.Drawing.Image]::FromFile((Join-Path $root "$After\sheet.png"))
$h = [math]::Max($a.Height, $b.Height) + 60
$out = New-Object System.Drawing.Bitmap ($a.Width + $b.Width + 36), $h
$g = [System.Drawing.Graphics]::FromImage($out)
$g.Clear([System.Drawing.Color]::FromArgb(12, 12, 16))
$font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$g.DrawString("BEFORE", $font, [System.Drawing.Brushes]::White, 12, 12)
$g.DrawString("AFTER", $font, [System.Drawing.Brushes]::White, ($a.Width + 36), 12)
$g.DrawImage($a, 12, 60, $a.Width, $a.Height)
$g.DrawImage($b, ($a.Width + 24), 60, $b.Width, $b.Height)
$g.Dispose()
$path = Join-Path $root "compare_${Before}_vs_${After}.png"
$out.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$a.Dispose(); $b.Dispose(); $out.Dispose()
Write-Host "Saved" $path
