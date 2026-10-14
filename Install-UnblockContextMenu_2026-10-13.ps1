<#
.SYNOPSIS
    Adds (or removes) an "Unblock" entry to the File Explorer right-click menu for files and folders.
    Current user only (HKCU); no admin rights needed.
.EXAMPLE
    .\Install-UnblockContextMenu_2026-10-13.ps1
    .\Install-UnblockContextMenu_2026-10-13.ps1 -Uninstall
#>
param([switch]$Uninstall)

$installDir = Join-Path $env:LOCALAPPDATA 'UnblockFile'
$target     = Join-Path $installDir 'Unblock-Files.ps1'
$source     = Join-Path $PSScriptRoot 'Unblock-Files_2026-10-13.ps1'
$keys       = 'Software\Classes\*\shell\UnblockFile', 'Software\Classes\Directory\shell\UnblockFile'

if ($Uninstall) {
    foreach ($k in $keys) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($k, $false) }
    Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Context menu entry removed.'
    return
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $target -Force

$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" "%1"' -f $target

foreach ($k in $keys) {
    $root = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($k)
    $root.SetValue('', 'Unblock')
    $root.SetValue('Icon', 'shell32.dll,47')
    $cmd = $root.CreateSubKey('command')
    $cmd.SetValue('', $command)
    $cmd.Close(); $root.Close()
}
Write-Host 'Context menu entry added. On Windows 11 it appears under "Show more options" (Shift+F10).'
