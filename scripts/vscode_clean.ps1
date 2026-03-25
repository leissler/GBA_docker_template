Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [ValidateSet("outputs", "all")]
  [string]$Mode = "outputs"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$CleanScript = Join-Path $ScriptDir "clean_all_outputs.ps1"

if ($Mode -eq "outputs") {
  & $CleanScript -Mode "host-docker"
  exit 0
}

& $CleanScript -Mode "host-docker"
$stampDir = Join-Path $WorkspaceRoot ".docker-stamps"
if (Test-Path $stampDir) {
  Remove-Item -Recurse -Force $stampDir
}
