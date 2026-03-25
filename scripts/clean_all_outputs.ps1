Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [ValidateSet("local", "host-docker")]
  [string]$Mode = "local"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$SourceDir = Join-Path $WorkspaceRoot "source"
$SourceDirMount = if ($env:GBA_SOURCE_DIR_MOUNT) { $env:GBA_SOURCE_DIR_MOUNT } else { $SourceDir }

function Resolve-ProjectName {
  $originUrl = ""
  try {
    $originUrl = (git -C $WorkspaceRoot config --get remote.origin.url 2>$null | Out-String).Trim()
  } catch {
    $originUrl = ""
  }

  if ($originUrl) {
    $name = [System.IO.Path]::GetFileName($originUrl)
    if ($name.EndsWith(".git")) {
      $name = $name.Substring(0, $name.Length - 4)
    }
    if ($name) {
      return $name
    }
  }

  return [System.IO.Path]::GetFileName($WorkspaceRoot)
}

function Resolve-ContainerRuntime {
  foreach ($candidate in @("docker", "podman")) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
      return $cmd.Source
    }
  }
  return $null
}

$projectName = Resolve-ProjectName
$romRootPath = Join-Path $WorkspaceRoot ("{0}.gba" -f $projectName)

foreach ($filePath in @($romRootPath, (Join-Path $WorkspaceRoot "source.gba"), (Join-Path $WorkspaceRoot "compile_commands.json"))) {
  if (Test-Path $filePath) {
    Remove-Item -Force $filePath
  }
}

foreach ($filePath in @(
  (Join-Path $SourceDir "source.gba"),
  (Join-Path $SourceDir "source.elf"),
  (Join-Path $SourceDir "source.map"),
  (Join-Path $SourceDir "source.sym"),
  (Join-Path $SourceDir "source.dis")
)) {
  if (Test-Path $filePath) {
    Remove-Item -Force $filePath
  }
}

foreach ($dirPath in @(
  (Join-Path $SourceDir "build"),
  (Join-Path $SourceDir "build_debug"),
  (Join-Path $SourceDir "build_release"),
  (Join-Path $SourceDir "build_dev_debug"),
  (Join-Path $SourceDir "build_dev_release"),
  (Join-Path $SourceDir "build_host_debug"),
  (Join-Path $SourceDir "build_host_release")
)) {
  if (Test-Path $dirPath) {
    Remove-Item -Recurse -Force $dirPath
  }
}

if ($Mode -eq "host-docker") {
  $runtime = Resolve-ContainerRuntime
  if ($runtime) {
    $containerCmd = "rm -f /source/source.gba /source/source.elf /source/source.map /source/source.sym /source/source.dis && rm -rf /source/build /source/build_debug /source/build_release /source/build_dev_debug /source/build_dev_release /source/build_host_debug /source/build_host_release"
    & $runtime run --rm -v "${SourceDirMount}:/source" dkarm_butano:local -l -c $containerCmd *> $null
  }
}

Write-Output ("Cleanup complete ({0})." -f $Mode)
