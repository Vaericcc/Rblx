# Pull the latest Dubble Take from GitHub and serve it to Roblox Studio with Rojo (Windows).
# Usage: .\scripts\sync.ps1            (pull + rojo serve)
#        .\scripts\sync.ps1 build      (pull + build DubbleTake.rbxl)
param([string]$Mode = "serve")
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$branch = git rev-parse --abbrev-ref HEAD
Write-Host "Pulling origin/$branch ..."
git pull --ff-only origin $branch

if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
  Write-Host "rojo not found on PATH. Install it with: rokit install   (or see https://rojo.space)"
  exit 1
}

if ($Mode -eq "build") {
  rojo build -o DubbleTake.rbxl
  Write-Host "Built DubbleTake.rbxl - open it in Studio."
} else {
  Write-Host "Serving. In Studio: Plugins -> Rojo -> Connect (localhost:34872)."
  rojo serve
}
