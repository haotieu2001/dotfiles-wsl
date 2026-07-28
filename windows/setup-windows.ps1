<#
.SYNOPSIS
  Installs the Windows half of this dotfiles setup: WezTerm, Hack Nerd Font,
  and a loader that points WezTerm at the config living inside WSL.

.DESCRIPTION
  In the macOS video these are Homebrew casks, installed declaratively by Nix.
  On Windows they cannot be: WezTerm draws the actual window and the font must
  be readable by the Windows font renderer, so both have to exist outside the
  WSL filesystem. This script is the honest, imperative replacement for that
  part of the Nix config. It is idempotent - re-running it is safe.

.PARAMETER Distro
  WSL distro name, as printed by `wsl -l -q`. Only needed if this script is not
  being run from its own location inside the WSL filesystem.

.PARAMETER WslUser
  Your WSL username. Same caveat as -Distro.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
#>
[CmdletBinding()]
param(
  [string]$Distro,
  [string]$WslUser
)

$ErrorActionPreference = 'Stop'
$FontVersion = '3.4.0'   # ryanoasis/nerd-fonts release tag

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Work out where the repo lives, as seen from Windows.
# ---------------------------------------------------------------------------
# If you launched this script from the WSL filesystem (the normal case, e.g.
# \\wsl.localhost\Ubuntu\home\you\dotfiles-wsl\windows), $PSScriptRoot already
# IS the UNC path we need, so nothing has to be guessed.
Info 'Locating the repo'
$repoRoot = Split-Path -Parent $PSScriptRoot

if ($repoRoot -like '\\wsl*') {
  Ok "Running from inside WSL: $repoRoot"
} else {
  if (-not $Distro)  { $Distro  = (wsl.exe -l -q | Where-Object { $_.Trim() } | Select-Object -First 1).Trim() }
  if (-not $WslUser) { $WslUser = (wsl.exe -d $Distro -e whoami).Trim() }
  # ~/.dotfiles is a symlink created by bootstrap.sh; resolve it to a real path
  # because the \\wsl.localhost bridge does not always follow Linux symlinks.
  $realPath = (wsl.exe -d $Distro -e readlink -f "/home/$WslUser/.dotfiles").Trim()
  if (-not $realPath) { throw "Could not resolve ~/.dotfiles inside $Distro. Run ./bootstrap.sh in WSL first." }
  $repoRoot = "\\wsl.localhost\$Distro" + ($realPath -replace '/', '\')
  Ok "Resolved repo to $repoRoot"
}

$weztermConfig = Join-Path $repoRoot 'home\.config\wezterm\wezterm.lua'
if (-not (Test-Path $weztermConfig)) { throw "Expected config not found at $weztermConfig" }

# ---------------------------------------------------------------------------
# 1. WezTerm
# ---------------------------------------------------------------------------
Info 'Installing WezTerm'
if (Get-Command wezterm.exe -ErrorAction SilentlyContinue) {
  Ok 'already installed, skipping'
} elseif (Get-Command winget.exe -ErrorAction SilentlyContinue) {
  winget install --id wez.wezterm --exact --source winget `
    --accept-package-agreements --accept-source-agreements
  Ok 'installed'
} else {
  Warn 'winget not available. Install WezTerm manually from https://wezterm.org'
}

# ---------------------------------------------------------------------------
# 2. Hack Nerd Font (per-user, no admin required)
# ---------------------------------------------------------------------------
# home.nix installs this font into the Linux fontconfig tree, which is enough
# for Linux GUI apps but invisible to a WezTerm running as a Windows process.
# So it must be installed on Windows as well.
Info "Installing Hack Nerd Font v$FontVersion"
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$fontReg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$faces   = @('Regular', 'Bold', 'Italic', 'BoldItalic')

$missing = $faces | Where-Object { -not (Test-Path (Join-Path $fontDir "HackNerdFont-$_.ttf")) }
if (-not $missing) {
  Ok 'all four faces already present, skipping'
} else {
  New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
  if (-not (Test-Path $fontReg)) { New-Item -Path $fontReg -Force | Out-Null }

  $tmp = Join-Path $env:TEMP "hack-nerd-$FontVersion"
  $zip = "$tmp.zip"
  $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v$FontVersion/Hack.zip"
  Ok "downloading $url"
  # Default PowerShell 5 TLS is too old for GitHub.
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force

  foreach ($face in $faces) {
    $file = Join-Path $tmp "HackNerdFont-$face.ttf"
    if (-not (Test-Path $file)) { Warn "missing $face in archive, skipping"; continue }
    $dest = Join-Path $fontDir "HackNerdFont-$face.ttf"
    Copy-Item $file $dest -Force
    # Windows only enumerates a font once it is registered. Per-user fonts go
    # in HKCU and take a full path as their value.
    # `else` must stay on the closing brace's line or PowerShell ends the statement.
    $label = if ($face -eq 'Regular') { 'Hack Nerd Font (TrueType)' } else { "Hack Nerd Font $face (TrueType)" }
    New-ItemProperty -Path $fontReg -Name $label -Value $dest -PropertyType String -Force | Out-Null
    Ok "installed $face"
  }
  Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Warn 'If WezTerm cannot find the font yet, sign out and back in once.'
}

# ---------------------------------------------------------------------------
# 3. The WezTerm loader stub
# ---------------------------------------------------------------------------
# WezTerm is a Windows process, so it cannot read a symlink that WSL created
# under /mnt/c. Rather than copying the config to Windows (which would drift),
# write a three-line stub that dofile()s the real config over \\wsl.localhost.
# add_to_config_reload_watch_list keeps WezTerm's hot reload working, so the
# edit-in-place property from the video survives.
Info 'Writing the WezTerm loader stub'
$stubPath = Join-Path $env:USERPROFILE '.wezterm.lua'
$stub = @"
-- Generated by dotfiles-wsl/windows/setup-windows.ps1 - do not edit.
-- The real config lives in the repo inside WSL; this only points at it.
local wezterm = require 'wezterm'
local wsl_config = [[$weztermConfig]]
wezterm.add_to_config_reload_watch_list(wsl_config)
return dofile(wsl_config)
"@

if ((Test-Path $stubPath) -and -not ((Get-Content $stubPath -Raw) -match 'setup-windows\.ps1')) {
  $backup = "$stubPath.backup"
  Copy-Item $stubPath $backup -Force
  Warn "existing hand-written .wezterm.lua backed up to $backup"
}
Set-Content -Path $stubPath -Value $stub -Encoding UTF8
Ok "wrote $stubPath -> $weztermConfig"

Write-Host ''
Info 'Windows side done. Launch WezTerm; it opens straight into WSL.'
Write-Host '    Optional Windows appearance tweaks: .\settings.ps1' -ForegroundColor Gray
