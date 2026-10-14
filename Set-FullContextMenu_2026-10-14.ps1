<#
.SYNOPSIS
    Restores the classic (full) right-click context menu in File Explorer on Windows 11.
    Current user only (HKCU); no admin rights needed.
.PARAMETER Revert
    Restores the default Windows 11 compact context menu.
.PARAMETER NoRestart
    Skips restarting Explorer (the change then applies after sign-out/sign-in).
.EXAMPLE
    .\Set-FullContextMenu_2026-10-14.ps1
    .\Set-FullContextMenu_2026-10-14.ps1 -Revert
#>
param(
    [switch]$Revert,
    [switch]$NoRestart
)

$clsid = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'

if ($Revert) {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($clsid, $false)
    Write-Host 'Default Windows 11 context menu restored.'
}
else {
    # An empty InprocServer32 default value makes Explorer fall back to the classic menu.
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$clsid\InprocServer32")
    $key.SetValue('', '')
    $key.Close()
    Write-Host 'Full context menu enabled.'
}

if (-not $NoRestart) {
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 2
    # Explorer normally relaunches itself; start it only if it didn't.
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}
