# PowerShell Scripts

A collection of PowerShell scripts to automate repetitive tasks and make sysadmin life easier.

## Scripts

| Script | Description |
|---|---|
| `Unblock-Files_2026-10-13.ps1` | Removes the Mark-of-the-Web (Zone.Identifier) from files, equivalent to ticking **Unblock** in Properties. Folders are processed recursively. |
| `Install-UnblockContextMenu_2026-10-13.ps1` | Adds an **Unblock** entry to the File Explorer right-click menu for files and folders (current user only, no admin rights). Use `-Uninstall` to remove it. |
| `Set-FullContextMenu_2026-10-14.ps1` | Restores the classic full right-click menu in Windows 11 File Explorer (no more "Show more options"). Use `-Revert` to go back to the default menu. |

## Usage

```powershell
# Add the right-click "Unblock" entry
powershell -ExecutionPolicy Bypass -File .\Install-UnblockContextMenu_2026-10-13.ps1

# Remove it
powershell -ExecutionPolicy Bypass -File .\Install-UnblockContextMenu_2026-10-13.ps1 -Uninstall

# Show the full right-click menu in Windows 11 (restarts Explorer)
powershell -ExecutionPolicy Bypass -File .\Set-FullContextMenu_2026-10-14.ps1

# Go back to the default Windows 11 menu
powershell -ExecutionPolicy Bypass -File .\Set-FullContextMenu_2026-10-14.ps1 -Revert
```

On Windows 11 the **Unblock** entry appears under **Show more options** (or Shift+right-click) unless the full context menu is enabled.

## Author

Imran Saeed — [LinkedIn](https://www.linkedin.com/in/ximran/)
