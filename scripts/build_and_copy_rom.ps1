param(
  [ValidateSet("release", "debug")]
  [string]$Mode = "release",
  [int]$BuildJobs = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$SourceDir = Join-Path $WorkspaceRoot "source"
$SourceDirMount = if ($env:GBA_SOURCE_DIR_MOUNT) { $env:GBA_SOURCE_DIR_MOUNT } else { $SourceDir }

$BaseImage = "dkarm_base:local"
$DuskImage = "dkarm_dusk:local"
$ButanoImage = "dkarm_butano:local"

function Resolve-ContainerRuntime {
  foreach ($candidate in @("docker", "podman")) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
      return $cmd.Source
    }
  }
  return $null
}

function Test-RuntimeReady {
  param([string]$RuntimeExe)
  try {
    & $RuntimeExe info *> $null
    return $LASTEXITCODE -eq 0
  } catch {
    return $false
  }
}

function Start-DockerDesktop {
  if (-not (Test-Path "C:\Program Files\Docker\Docker\Docker Desktop.exe")) {
    return
  }
  Start-Process -FilePath "C:\Program Files\Docker\Docker\Docker Desktop.exe" | Out-Null
}

function Ensure-ContainerRuntimeReady {
  param([string]$RuntimeExe)

  if (Test-RuntimeReady -RuntimeExe $RuntimeExe) {
    return
  }

  $runtimeName = [System.IO.Path]::GetFileName($RuntimeExe).ToLowerInvariant()
  if ($runtimeName -eq "docker.exe" -or $runtimeName -eq "docker") {
    Write-Output "Docker daemon is not running. Starting Docker Desktop..."
    Start-DockerDesktop
    for ($i = 0; $i -lt 60; $i++) {
      Start-Sleep -Seconds 1
      if (Test-RuntimeReady -RuntimeExe $RuntimeExe) {
        Write-Output "Docker Desktop is ready."
        return
      }
    }
    throw "Timed out waiting for Docker Desktop."
  }

  throw "Container runtime '$RuntimeExe' is installed but not running."
}

function Get-DockerContextHost {
  param([string]$RuntimeExe)
  $runtimeName = [System.IO.Path]::GetFileName($RuntimeExe).ToLowerInvariant()
  if ($runtimeName -ne "docker.exe" -and $runtimeName -ne "docker") {
    return ""
  }

  try {
    $out = & $RuntimeExe context inspect --format '{{ (index .Endpoints "docker").Host }}' 2>$null
    if ($LASTEXITCODE -ne 0) {
      return ""
    }
    return ($out | Out-String).Trim()
  } catch {
    return ""
  }
}

function Ensure-Image {
  param(
    [string]$RuntimeExe,
    [string]$ImageName,
    [string]$DockerfilePath
  )

  $exists = $false
  try {
    & $RuntimeExe image inspect $ImageName 1>$null 2>$null
    $exists = ($LASTEXITCODE -eq 0)
  } catch {
    $exists = $false
  }

  if ($exists) {
    return
  }

  Write-Output "Docker image $ImageName not found, building it..."
  & $RuntimeExe build -f $DockerfilePath -t $ImageName $WorkspaceRoot
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to build image $ImageName."
  }
}

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

function Try-FetchRomFromMountedSource {
  param(
    [string]$RuntimeExe,
    [string]$ImageName,
    [string]$MountSource,
    [string]$RomOutPath
  )

  $containerId = ""
  try {
    $containerId = (& $RuntimeExe create -v "${MountSource}:/source:ro" $ImageName -c "sleep 300" 2>$null | Out-String).Trim()
    if (-not $containerId) {
      return $false
    }

    & $RuntimeExe start $containerId 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
      return $false
    }

    & $RuntimeExe exec $containerId test -f /source/source.gba 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
      return $false
    }

    & $RuntimeExe cp "${containerId}:/source/source.gba" $RomOutPath 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
      return $false
    }

    return $true
  } catch {
    return $false
  } finally {
    if ($containerId) {
      & $RuntimeExe rm -f $containerId 1>$null 2>$null
    }
  }
}

$runtime = Resolve-ContainerRuntime
if (-not $runtime) {
  throw "No supported container runtime found. Install Docker Desktop or Podman."
}

Ensure-ContainerRuntimeReady -RuntimeExe $runtime

$daemonHost = Get-DockerContextHost -RuntimeExe $runtime
if ($daemonHost -and -not $daemonHost.StartsWith("unix://") -and -not $daemonHost.StartsWith("npipe://")) {
  if (-not $env:GBA_SOURCE_DIR_MOUNT) {
    throw "Detected remote Docker daemon '$daemonHost'. Set GBA_SOURCE_DIR_MOUNT to a source path on the daemon host."
  }
}

Ensure-Image -RuntimeExe $runtime -ImageName $BaseImage -DockerfilePath (Join-Path $WorkspaceRoot "docker/base/Dockerfile")
Ensure-Image -RuntimeExe $runtime -ImageName $DuskImage -DockerfilePath (Join-Path $WorkspaceRoot "docker/dusk/Dockerfile")
Ensure-Image -RuntimeExe $runtime -ImageName $ButanoImage -DockerfilePath (Join-Path $WorkspaceRoot "docker/butano/Dockerfile")

$buildCmd = if ($Mode -eq "debug") {
  "make -j$BuildJobs BUILD=build_host_debug USERFLAGS='-Og -g3' USERCXXFLAGS='-Og -g3'"
} else {
  "make -j$BuildJobs BUILD=build_host_release"
}

& $runtime run -it --rm -v "${SourceDirMount}:/source" $ButanoImage -l -c $buildCmd
if ($LASTEXITCODE -ne 0) {
  throw "Build failed with exit code $LASTEXITCODE."
}

$romInSource = Join-Path $SourceDir "source.gba"
$projectName = Resolve-ProjectName
$romOut = Join-Path $WorkspaceRoot ("{0}.gba" -f $projectName)

if (-not (Test-Path $romInSource)) {
  $fetched = Try-FetchRomFromMountedSource -RuntimeExe $runtime -ImageName $ButanoImage -MountSource $SourceDirMount -RomOutPath $romInSource
  if (-not $fetched) {
    throw "Build succeeded but source/source.gba was not found and could not be fetched from mounted source path. Verify GBA_SOURCE_DIR_MOUNT."
  }
}

Copy-Item -Force $romInSource $romOut
Write-Output ("Created ./{0}.gba" -f $projectName)
