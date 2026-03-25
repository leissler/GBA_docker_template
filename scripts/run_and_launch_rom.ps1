param(
  [ValidateSet("release", "debug")]
  [string]$Mode = "release",
  [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildScript = Join-Path $ScriptDir "build_and_copy_rom.ps1"
$StartBridgeScript = Join-Path $ScriptDir "start_mgba_bridge.ps1"
$LaunchScript = Join-Path $ScriptDir "launch_mgba_via_bridge.ps1"

if (-not $NoBuild) {
  & $BuildScript -Mode $Mode
  if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
  }
}

$oldGbaDebug = $env:GBA_DEBUG
$oldMgbaDebug = $env:MGBA_DEBUG

try {
  if ($Mode -eq "debug") {
    $env:GBA_DEBUG = "1"
    $env:MGBA_DEBUG = "1"
  } else {
    $env:GBA_DEBUG = "0"
    $env:MGBA_DEBUG = "0"
  }

  & $StartBridgeScript
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to start emulator bridge (exit code $LASTEXITCODE)."
  }

  & $LaunchScript
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to launch emulator via bridge (exit code $LASTEXITCODE)."
  }
} finally {
  $env:GBA_DEBUG = $oldGbaDebug
  $env:MGBA_DEBUG = $oldMgbaDebug
}
