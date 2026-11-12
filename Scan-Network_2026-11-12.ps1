<#
.SYNOPSIS
    Quickly lists every live device on the local subnet (IP, hostname, MAC) and flags devices not seen on a previous scan.

.DESCRIPTION
    1. Detects the subnet of the active network adapter (or uses -Network).
    2. Pings every address in parallel, which takes a few seconds for a /24.
    3. Reads the ARP table afterwards, so devices that block ping but still answer ARP are listed too.
    4. Resolves hostnames in parallel.
    5. Compares against the devices seen on earlier scans of this network and marks new ones with NEW.
       The first scan of a network only saves the baseline.

    No admin rights needed. Works on Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER Network
    Subnet to scan in CIDR notation, e.g. 192.168.1.0/24. Default: the subnet of the active adapter. Supported: /20 to /30.

.PARAMETER TimeoutMs
    How long to wait for each ping reply. Default 1000.

.PARAMETER NoResolve
    Skips hostname lookups.

.PARAMETER PassThru
    Also returns the results as objects (for Export-Csv etc.).

.EXAMPLE
    .\Scan-Network_2026-11-12.ps1

.EXAMPLE
    .\Scan-Network_2026-11-12.ps1 -Network 10.0.5.0/24 -PassThru | Export-Csv devices.csv -NoTypeInformation
#>
[CmdletBinding()]
param(
    [string]$Network,
    [int]$TimeoutMs = 1000,
    [switch]$NoResolve,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$max32 = [uint64]4294967295

function ConvertTo-IPv4Number([string]$Ip) {
    $b = [System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
    [Array]::Reverse($b)
    [uint64][BitConverter]::ToUInt32($b, 0)
}

function ConvertFrom-IPv4Number([uint64]$Number) {
    $b = [BitConverter]::GetBytes([uint32]$Number)
    [Array]::Reverse($b)
    [System.Net.IPAddress]::new($b).ToString()
}

# --- Work out the subnet -----------------------------------------------------
if ($Network) {
    if ($Network -match '^(\d{1,3}(\.\d{1,3}){3})/(\d{1,2})$') {
        $baseIp = $Matches[1]
        $prefix = [int]$Matches[3]
    }
    else {
        throw "Invalid -Network '$Network'. Use CIDR notation, e.g. 192.168.1.0/24."
    }
}
else {
    $cfg = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' } |
        Sort-Object { $_.IPv4Interface.InterfaceMetric } |
        Select-Object -First 1
    if (-not $cfg) { throw 'No active network connection with a default gateway found. Use -Network.' }
    $baseIp = $cfg.IPv4Address[0].IPAddress
    $prefix = $cfg.IPv4Address[0].PrefixLength
}

if ($prefix -lt 20 -or $prefix -gt 30) { throw "Prefix /$prefix is not supported. Use /20 to /30." }

$mask      = ([uint64]($max32 -shl (32 - $prefix))) -band $max32
$netNumber = (ConvertTo-IPv4Number $baseIp) -band $mask
$bcNumber  = $netNumber -bor ((-bnot $mask) -band $max32)
$netAddr   = ConvertFrom-IPv4Number $netNumber

$ips = [System.Collections.Generic.List[string]]::new()
for ($n = $netNumber + 1; $n -lt $bcNumber; $n++) { $ips.Add((ConvertFrom-IPv4Number $n)) }

# Own addresses and gateways, used for labelling
$localIps = @{}
foreach ($a in Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue) { $localIps[$a.IPAddress] = $a.InterfaceIndex }
$gateways = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne '0.0.0.0' } | ForEach-Object { $_.NextHop })

Write-Host ("Scanning {0}/{1} ({2} addresses)..." -f $netAddr, $prefix, $ips.Count) -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# --- Parallel ping sweep -----------------------------------------------------
$pings = foreach ($ip in $ips) {
    $p = [System.Net.NetworkInformation.Ping]::new()
    [pscustomobject]@{ IP = $ip; Ping = $p; Task = $p.SendPingAsync($ip, $TimeoutMs) }
}
try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($pings.Task)) } catch { }

$alive = @{}
foreach ($p in $pings) {
    if ($p.Task.Status -eq 'RanToCompletion' -and $p.Task.Result.Status -eq 'Success') { $alive[$p.IP] = $true }
    $p.Ping.Dispose()
}

# --- ARP table: catches devices that ignore ping, and gives MAC addresses ----
$arp = @{}
$neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.State -in 'Reachable', 'Stale', 'Delay', 'Probe' -and $_.LinkLayerAddress }
foreach ($nb in $neighbors) {
    $num = ConvertTo-IPv4Number $nb.IPAddress
    if ($num -gt $netNumber -and $num -lt $bcNumber) { $arp[$nb.IPAddress] = $nb.LinkLayerAddress.ToUpper() }
}

$found = foreach ($ip in $ips) {
    $isLocal = $localIps.ContainsKey($ip)
    if (-not ($alive.ContainsKey($ip) -or $arp.ContainsKey($ip) -or $isLocal)) { continue }

    $mac = $arp[$ip]
    if ($isLocal) {
        $adapter = Get-NetAdapter -InterfaceIndex $localIps[$ip] -ErrorAction SilentlyContinue
        if ($adapter) { $mac = $adapter.MacAddress }
    }

    [pscustomobject]@{
        IP       = $ip
        Hostname = ''
        MAC      = $mac
        Status   = if ($alive.ContainsKey($ip) -or $isLocal) { 'Replied' } else { 'ARP only' }
        Note     = ''
    }
}
$found = @($found)

# --- Parallel hostname lookup ------------------------------------------------
if (-not $NoResolve -and $found.Count) {
    $lookups = foreach ($d in $found) { [pscustomobject]@{ Device = $d; Task = [System.Net.Dns]::GetHostEntryAsync($d.IP) } }
    try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($lookups.Task), 4000) } catch { }
    foreach ($l in $lookups) {
        if ($l.Task.Status -eq 'RanToCompletion' -and $l.Task.Result.HostName -ne $l.Device.IP) {
            $l.Device.Hostname = $l.Task.Result.HostName
        }
    }
}

# --- Compare with previously seen devices ------------------------------------
$stateDir  = Join-Path $env:LOCALAPPDATA 'Scan-Network'
$stateFile = Join-Path $stateDir ('known_{0}_{1}.json' -f $netAddr.Replace('.', '-'), $prefix)
$known = $null
if (Test-Path -LiteralPath $stateFile) {
    # The ForEach-Object unrolls the array that Windows PowerShell 5.1's ConvertFrom-Json returns as one object
    $known = @(Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json | ForEach-Object { $_ })
}

foreach ($d in $found) {
    $notes = [System.Collections.Generic.List[string]]::new()
    $key = if ($d.MAC) { $d.MAC } else { $d.IP }
    $d | Add-Member -NotePropertyName Key -NotePropertyValue $key

    if ($localIps.ContainsKey($d.IP)) { $notes.Add('This PC') }
    if ($gateways -contains $d.IP) { $notes.Add('Gateway') }
    if ($d.MAC -and (([Convert]::ToInt32($d.MAC.Substring(0, 2), 16) -band 2) -ne 0)) { $notes.Add('Private MAC') }
    if ($null -ne $known -and $known -notcontains $key) { $notes.Add('NEW') }
    $d.Note = $notes -join ', '
}

$found = @($found | Sort-Object { [version]$_.IP })
$sw.Stop()

# --- Report ------------------------------------------------------------------
Write-Host ''
$found | Format-Table IP, Hostname, MAC, Status, Note -AutoSize | Out-Host
Write-Host ("{0} devices found in {1:N1}s." -f $found.Count, $sw.Elapsed.TotalSeconds)

if ($null -eq $known) {
    Write-Host 'First scan of this network: baseline saved. Devices that appear later will be flagged NEW.' -ForegroundColor Yellow
}
else {
    $new = @($found | Where-Object { $_.Note -match 'NEW' })
    if ($new.Count) {
        Write-Host ("New since last scan: {0}" -f (($new | ForEach-Object { $_.IP }) -join ', ')) -ForegroundColor Green
    }
    else {
        Write-Host 'No new devices since the last scan.'
    }
}
if ($found | Where-Object { $_.Note -match 'Private MAC' }) {
    Write-Host 'Private MAC = randomized Wi-Fi address (typical for phones); the MAC changes per network.' -ForegroundColor DarkGray
}

# Save everything ever seen on this network
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$seen = @($known) + @($found | ForEach-Object { $_.Key }) | Where-Object { $_ } | Sort-Object -Unique
ConvertTo-Json -InputObject @($seen) | Set-Content -LiteralPath $stateFile -Encoding UTF8

if ($PassThru) { $found | Select-Object IP, Hostname, MAC, Status, Note }
