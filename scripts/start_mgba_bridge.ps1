Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$BridgeScript = Join-Path $ScriptDir "mgba_host_bridge.py"
$ConfigFile = if ($env:GBA_BRIDGE_CONFIG) { $env:GBA_BRIDGE_CONFIG } else { Join-Path $WorkspaceRoot ".emulator-bridge.env" }
$Port = if ($env:GBA_BRIDGE_PORT) { $env:GBA_BRIDGE_PORT } elseif ($env:MGBA_BRIDGE_PORT) { $env:MGBA_BRIDGE_PORT } else { "17777" }
$BridgeBind = if ($env:GBA_BRIDGE_BIND) { $env:GBA_BRIDGE_BIND } elseif ($env:MGBA_BRIDGE_BIND) { $env:MGBA_BRIDGE_BIND } else { "0.0.0.0" }
$RestartBridge = if ($env:GBA_BRIDGE_RESTART) { $env:GBA_BRIDGE_RESTART } else { "1" }
$Emulator = if ($env:GBA_EMULATOR) { $env:GBA_EMULATOR } else { "mgba" }
$EmulatorBin = if ($env:GBA_EMULATOR_BIN) { $env:GBA_EMULATOR_BIN } elseif ($env:MGBA_BIN) { $env:MGBA_BIN } else { "" }
$LogFile = if ($env:GBA_BRIDGE_LOG_FILE) { $env:GBA_BRIDGE_LOG_FILE } else { Join-Path $env:TEMP "mgba-host-bridge.log" }
$ErrLogFile = "${LogFile}.err"
$InitLog = Join-Path $WorkspaceRoot ".devcontainer\mgba-bridge-init.log"

function Write-InitLog {
  param([string]$Message)
  $dir = Split-Path -Parent $InitLog
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Add-Content -Path $InitLog -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

function Load-EnvFile {
  param([string]$PathToFile)
  if (-not (Test-Path $PathToFile)) {
    return
  }

  Get-Content -Path $PathToFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      return
    }

    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)\s*$') {
      $name = $matches[1]
      $value = $matches[2].Trim()
      if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        if ($value.Length -ge 2) {
          $value = $value.Substring(1, $value.Length - 2)
        }
      }
      Set-Item -Path ("Env:{0}" -f $name) -Value $value
    }
  }
}

function Test-BridgeRunning {
  try {
    Invoke-RestMethod -Method Get -Uri ("http://127.0.0.1:{0}/health" -f $Port) -TimeoutSec 1 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Stop-Bridge {
  try {
    Invoke-RestMethod -Method Post -Uri ("http://127.0.0.1:{0}/shutdown" -f $Port) -TimeoutSec 1 | Out-Null
  } catch {
    # Ignore and continue with wait checks.
  }

  for ($i = 0; $i -lt 20; $i++) {
    if (-not (Test-BridgeRunning)) {
      return $true
    }
    Start-Sleep -Milliseconds 100
  }

  return $false
}

function Resolve-Python {
  if ($env:PYTHON_BIN) {
    return @{ Exe = $env:PYTHON_BIN; Prefix = @() }
  }

  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    return @{ Exe = $py.Source; Prefix = @("-3") }
  }

  foreach ($candidate in @("python3", "python")) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
      return @{ Exe = $cmd.Source; Prefix = @() }
    }
  }

  return $null
}

Write-InitLog "start_mgba_bridge.ps1 invoked"

Load-EnvFile -PathToFile $ConfigFile

$Port = if ($env:GBA_BRIDGE_PORT) { $env:GBA_BRIDGE_PORT } elseif ($env:MGBA_BRIDGE_PORT) { $env:MGBA_BRIDGE_PORT } else { $Port }
$BridgeBind = if ($env:GBA_BRIDGE_BIND) { $env:GBA_BRIDGE_BIND } elseif ($env:MGBA_BRIDGE_BIND) { $env:MGBA_BRIDGE_BIND } else { $BridgeBind }
$RestartBridge = if ($env:GBA_BRIDGE_RESTART) { $env:GBA_BRIDGE_RESTART } else { $RestartBridge }
$Emulator = if ($env:GBA_EMULATOR) { $env:GBA_EMULATOR } else { $Emulator }
$EmulatorBin = if ($env:GBA_EMULATOR_BIN) { $env:GBA_EMULATOR_BIN } elseif ($env:MGBA_BIN) { $env:MGBA_BIN } else { $EmulatorBin }

$python = Resolve-Python
if (-not $python) {
  Write-Output "Python not found on host; cannot start emulator bridge automatically."
  Write-InitLog "failed: python not found"
  exit 0
}

if (Test-BridgeRunning) {
  if ($RestartBridge -eq "1") {
    Write-Output ("Restarting host emulator bridge on port {0}..." -f $Port)
    if (-not (Stop-Bridge)) {
      Write-Output ("Warning: could not fully stop existing bridge on port {0}; continuing." -f $Port)
    }
  } else {
    Write-InitLog ("bridge already running on {0}" -f $Port)
    exit 0
  }
}

$argsList = @()
$argsList += $python.Prefix
$argsList += @(
  "-u",
  $BridgeScript,
  "--host", $BridgeBind,
  "--port", "$Port",
  "--workspace-root", $WorkspaceRoot,
  "--emulator", $Emulator
)

if ($EmulatorBin) {
  $argsList += @("--emulator-bin", $EmulatorBin)
}

Start-Process -FilePath $python.Exe -ArgumentList $argsList -WindowStyle Hidden -RedirectStandardOutput $LogFile -RedirectStandardError $ErrLogFile | Out-Null

for ($i = 0; $i -lt 20; $i++) {
  if (Test-BridgeRunning) {
    Write-Output ("Host emulator bridge started on port {0} (emulator: {1})." -f $Port, $Emulator)
    Write-InitLog ("started bridge on {0} (emulator: {1})" -f $Port, $Emulator)
    exit 0
  }
  Start-Sleep -Milliseconds 200
}

Write-Output ("Failed to start host emulator bridge. See {0}" -f $LogFile)
Write-InitLog ("failed: see {0}" -f $LogFile)
exit 0
