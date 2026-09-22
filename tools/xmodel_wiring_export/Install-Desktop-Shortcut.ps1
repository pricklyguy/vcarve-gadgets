<#
.SYNOPSIS
  One-time setup: creates a "PGC Wiring Export" shortcut on your Desktop.

.DESCRIPTION
  Run this once (double-click it, or right-click > Run with PowerShell).
  It creates a Desktop shortcut that launches PGC_Wiring_Export_GUI.ps1
  with no visible console window - just the app window.

  Safe to run again later (e.g. if you move this folder) to recreate the
  shortcut pointing at the new location.
#>

$ErrorActionPreference = "Stop"

$guiScript = Join-Path $PSScriptRoot "PGC_Wiring_Export_GUI.ps1"

if (-not (Test-Path -LiteralPath $guiScript)) {
    Write-Error "Can't find PGC_Wiring_Export_GUI.ps1 next to this installer. Expected: $guiScript"
    exit 1
}

$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "PGC Wiring Export.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File `"$guiScript`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = "Convert an xLights .xmodel export into a wiring-path DXF for VCarve"
$shortcut.IconLocation = "powershell.exe,0"
$shortcut.Save()

Write-Host "Created desktop shortcut: $shortcutPath"
Write-Host "Double-click it any time to open the PGC Wiring Export window."
