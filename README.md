# GBA Docker Template

Build Game Boy Advance ROMs in Docker, without installing `devkitARM` on your host.

This README has two paths:
- `Path A`: content users (swap graphics/audio, build and test ROM from terminal)
- `Path B`: developers (VS Code + Dev Containers + debug with mGBA)

## Prerequisites

- Docker Desktop (or Podman)
- `make`
- `git`

Run all commands from the repository root.

## Path A: Content Users (No VS Code Needed)

Use this if you mainly edit assets and just want to build/test ROMs.

### 1. Build the Butano image once

```sh
make docker-build-butano
```

### 2. Edit project files

- Code: `source/src/`
- Graphics: `source/graphics/`
- Audio: `source/audio/` and `source/dmg_audio/`

### 3. Build ROM (release)

```sh
make AUTO_CLEAN_MAKE=0 compile-butano "CMD=make -j4 BUILD=build_host_release"
```

### 4. ROM output

- Main build output: `source/source.gba`
- Convenience copy in repo root: `./<repo-folder-name>.gba`

### Optional: debug-style host build

```sh
make AUTO_CLEAN_MAKE=0 compile-butano "CMD=make -j4 BUILD=build_host_debug USERFLAGS='-Og -g3' USERCXXFLAGS='-Og -g3'"
```

### Clean everything

```sh
bash scripts/clean_all_outputs.sh host-docker
make clean-docker-stamps
```

## Path B: Developers (VS Code + Dev Container)

Use this if you want IntelliSense, tasks, and one-key debug flow.

### 1. Open in container

1. Install VS Code extension: `Dev Containers`.
2. Open this repo in VS Code.
3. Run `Dev Containers: Reopen in Container`.

### 2. Build from VS Code

Run `Tasks: Run Build Task`:
- `Build ROM (debug)`
- `Build ROM (release)`

### 3. Clean from VS Code

Run `Tasks: Run Task`:
- `Clean All Outputs (devcontainer/local)`
- `Clean All Outputs (host via Docker)`
- `Clean Docker Stamps`
- `Clean Everything (host via Docker + stamps)`

### 4. Debug on host mGBA from container

Press `F5` and choose:
- `Attach to mGBA GDB stub (host:2345)`

If host bridge is not reachable, run on host:

```sh
bash scripts/start_mgba_bridge.sh
```

Bridge log (host):

```sh
cat /tmp/mgba-host-bridge.log
```

## Notes

- Docker Desktop auto-start is supported on macOS and on WSL2 Ubuntu.
- Build directories are separated to avoid stale dependency conflicts:
  `build_dev_*` for devcontainer tasks, `build_host_*` for host-via-Docker tasks.
