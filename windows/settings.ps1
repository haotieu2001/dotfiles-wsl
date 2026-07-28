<#
.SYNOPSIS
  The Windows counterpart of the video's `system.defaults` block in
  configuration.nix - dark theme, fast key repeat, auto-hiding taskbar, etc.

.DESCRIPTION
  Be clear-eyed about what this is. On macOS, nix-darwin writes these settings
  as part of the same declarative build as everything else, so they are covered
  by the reproducibility guarantee. Windows has no such interface: these are
  registry writes, run imperatively, and nothing reverts them if you change a
  setting by hand later. It is idempotent and re-runnable, which is the most
  that can honestly be claimed.

  Nothing here needs administrator rights - every value is under HKCU.
  Run .\settings.ps1 -WhatIf to see the changes without applying them.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\settings.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }

function Set-Reg {
  # Needs its own CmdletBinding so -WhatIf from the caller reaches ShouldProcess.
  [CmdletBinding(SupportsShouldProcess)]
  param($Path, $Name, $Value, $Type = 'DWord')
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  if ($PSCmdlet.ShouldProcess("$Path\$Name", "set to $Value")) {
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Ok "$Name = $Value"
  }
}

$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$advanced    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$keyboard    = 'HKCU:\Control Panel\Keyboard'
$touchpad    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'

# macOS: NSGlobalDomain.AppleInterfaceStyle = "Dark"
Info 'Dark theme'
Set-Reg $personalize 'AppsUseLightTheme'   0
Set-Reg $personalize 'SystemUsesLightTheme' 0

# macOS: KeyRepeat = 2 (fast) and InitialKeyRepeat = 15 (short delay).
# Windows inverts both scales: KeyboardSpeed is 0..31 where 31 is fastest,
# KeyboardDelay is 0..3 where 0 is the shortest delay. Stored as strings.
Info 'Fast key repeat'
Set-Reg $keyboard 'KeyboardSpeed' '31' 'String'
Set-Reg $keyboard 'KeyboardDelay' '0'  'String'

# macOS: AppleShowAllExtensions = true
Info 'Explorer: show file extensions and hidden files'
Set-Reg $advanced 'HideFileExt' 0
Set-Reg $advanced 'Hidden'      1

# macOS: finder.CreateDesktop = false (a desktop showing only the wallpaper)
Info 'Clean desktop'
Set-Reg $advanced 'HideIcons' 1

# macOS: trackpad.Clicking = true
Info 'Tap to click'
Set-Reg $touchpad 'TapsEnabled' 1

# macOS: dock.autohide = true and _HIHideMenuBar = true. Windows has one bar
# doing both jobs. Its state lives in a binary blob; byte 8 bit 0 is autohide,
# so read-modify-write instead of overwriting the whole structure.
Info 'Auto-hide the taskbar'
$stuck = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
if (Test-Path $stuck) {
  $settings = (Get-ItemProperty -Path $stuck -Name Settings).Settings
  if ($settings[8] -band 1) {
    Ok 'already auto-hiding'
  } elseif ($PSCmdlet.ShouldProcess("$stuck\Settings", 'enable auto-hide')) {
    $settings[8] = $settings[8] -bor 1
    Set-ItemProperty -Path $stuck -Name Settings -Value $settings
    Ok 'enabled'
  }
} else {
  Write-Host '    StuckRects3 not found, skipping' -ForegroundColor Yellow
}

# There is no faithful Windows equivalent of finder.FXPreferredViewStyle = "Nlsv".
# Explorer's per-folder view state is cached in BagMRU/Bags and is not a single
# documented value, so it is left alone rather than written unreliably.

Info 'Restarting Explorer so the changes take effect'
if ($PSCmdlet.ShouldProcess('explorer.exe', 'restart')) {
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
  if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
  Ok 'done'
}

Write-Host ''
Write-Host 'Key repeat rate applies to new windows; sign out and back in to be sure.' -ForegroundColor Gray
