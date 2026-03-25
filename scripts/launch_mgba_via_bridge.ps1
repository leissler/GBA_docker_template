Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Port = if ($env:GBA_BRIDGE_PORT) { [int]$env:GBA_BRIDGE_PORT } elseif ($env:MGBA_BRIDGE_PORT) { [int]$env:MGBA_BRIDGE_PORT } else { 17777 }
$BridgeHostOverride = if ($env:GBA_BRIDGE_HOST) { $env:GBA_BRIDGE_HOST } elseif ($env:MGBA_BRIDGE_HOST) { $env:MGBA_BRIDGE_HOST } else { "" }
$RomPath = "source/source.gba"
$DebugRaw = if ($env:GBA_DEBUG) { $env:GBA_DEBUG } elseif ($env:MGBA_DEBUG) { $env:MGBA_DEBUG } else { "1" }
$EmulatorOverride = if ($env:GBA_EMULATOR) { $env:GBA_EMULATOR } else { "" }
$EmulatorBinOverride = if ($env:GBA_EMULATOR_BIN) { $env:GBA_EMULATOR_BIN } elseif ($env:MGBA_BIN) { $env:MGBA_BIN } else { "" }

function Parse-Bool {
  param([string]$Raw, [bool]$Default = $true)
  if (-not $Raw) { return $Default }
  switch ($Raw.Trim().ToLowerInvariant()) {
    "1" { return $true }
    "true" { return $true }
    "yes" { return $true }
    "on" { return $true }
    "0" { return $false }
    "false" { return $false }
    "no" { return $false }
    "off" { return $false }
    default { return $Default }
  }
}

function Test-BridgeHealth {
  param([string]$HostName, [int]$BridgePort)
  try {
    Invoke-RestMethod -Method Get -Uri ("http://{0}:{1}/health" -f $HostName, $BridgePort) -TimeoutSec 1 | Out-Null
    return $true
  } catch {
    return $false
  }
}

$candidates = New-Object System.Collections.Generic.List[string]
if ($BridgeHostOverride) {
  $candidates.Add($BridgeHostOverride)
}
$candidates.Add("host.docker.internal")
$candidates.Add("gateway.docker.internal")
$candidates.Add("host.containers.internal")
$candidates.Add("docker.for.mac.host.internal")
$candidates.Add("127.0.0.1")
$candidates.Add("localhost")

$bridgeHost = $null
foreach ($candidate in $candidates) {
  if (Test-BridgeHealth -HostName $candidate -BridgePort $Port) {
    $bridgeHost = $candidate
    break
  }
}

if (-not $bridgeHost) {
  throw ("Host emulator bridge is not reachable on port {0}. Checked hosts: {1}" -f $Port, ($candidates -join ", "))
}

$payload = @{
  rom = $RomPath
  debug = (Parse-Bool -Raw $DebugRaw -Default $true)
}
if ($EmulatorOverride) {
  $payload["emulator"] = $EmulatorOverride
}
if ($EmulatorBinOverride) {
  $payload["emulator_bin"] = $EmulatorBinOverride
}

$json = $payload | ConvertTo-Json -Compress

try {
  $response = Invoke-RestMethod -Method Post -Uri ("http://{0}:{1}/launch" -f $bridgeHost, $Port) -ContentType "application/json" -Body $json -TimeoutSec 12
} catch {
  throw "Host emulator bridge launch failed: $($_.Exception.Message)"
}

if (-not $response.ok) {
  throw ("Host emulator bridge launch returned error: {0}" -f ($response | ConvertTo-Json -Compress))
}

Write-Output ("Requested host emulator launch for {0}" -f $RomPath)
