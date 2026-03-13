# GBA Docker Template

Build Game Boy Advance ROMs in Docker, without installing `devkitARM` on your host.

Two ways to use this repo:
- `Path A`: terminal-only users (edit assets/code and build ROM)
- `Path B`: VS Code developers (Dev Container + IntelliSense + debug)

## Prerequisites

- Docker Desktop (or Podman)
- `make`
- `git`

Run all commands from the repository root.

## Path A: Build and Test Without VS Code

### 1. Edit project files

- Code: `source/src/`
- Graphics: `source/graphics/`
- Audio: `source/audio/` and `source/dmg_audio/`

### 2. Build ROM (release)

```sh
make AUTO_CLEAN_MAKE=0 compile-butano "CMD=make -j4 BUILD=build_host_release"
```

`make docker-build-butano` is optional. `compile-butano` already builds the image automatically when needed.

### 3. ROM output

- Main build output: `source/source.gba`
- Convenience copy in repo root: `./<repo-folder-name>.gba`

### 4. Optional debug build

```sh
make AUTO_CLEAN_MAKE=0 compile-butano "CMD=make -j4 BUILD=build_host_debug USERFLAGS='-Og -g3' USERCXXFLAGS='-Og -g3'"
```

### 5. Clean all generated files

```sh
bash scripts/clean_all_outputs.sh host-docker
make clean-docker-stamps
```

## Path B: Developers (VS Code + Dev Container)

### 1. Open in Dev Container

1. Install the `Dev Containers` VS Code extension.
2. Open this repo in VS Code.
3. Run `Dev Containers: Reopen in Container`.

### 2. Build ROM in VS Code

Use `Tasks: Run Build Task`:
- `Build ROM (debug)`
- `Build ROM (release)`

### 3. Clean in VS Code

Use `Tasks: Run Task`:
- `Clean All Outputs (devcontainer/local)`
- `Clean All Outputs (host via Docker)`
- `Clean Everything (host via Docker + stamps)`

### 4. Debug on host mGBA

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
