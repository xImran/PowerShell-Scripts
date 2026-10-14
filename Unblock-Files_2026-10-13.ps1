<#
.SYNOPSIS
    Removes the Mark-of-the-Web (Zone.Identifier) from files, same as ticking "Unblock" in Properties.
.PARAMETER Path
    One or more files or folders. Folders are processed recursively.
#>
param(
    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [string[]]$Path
)

foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    if (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
            Unblock-File -ErrorAction SilentlyContinue
    }
    else {
        Unblock-File -LiteralPath $p -ErrorAction SilentlyContinue
    }
}
