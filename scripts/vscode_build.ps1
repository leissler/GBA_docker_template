param(
  [ValidateSet("debug", "release")]
  [string]$Mode = "debug"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildScript = Join-Path $ScriptDir "build_and_copy_rom.ps1"

& $BuildScript -Mode $Mode
if ($LASTEXITCODE -ne 0) {
  throw "Build failed with exit code $LASTEXITCODE."
}
