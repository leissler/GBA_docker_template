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

## Windows 11 Setup (WSL2 + Docker Desktop)

1. Install WSL2 (PowerShell as Administrator):

```powershell
wsl --install
wsl --set-default-version 2
```

2. Install Docker Desktop for Windows.
3. In Docker Desktop:
   - `Settings > General`: enable `Use the WSL 2 based engine`
   - `Settings > Resources > WSL Integration`: enable your Ubuntu distro
4. Verify your distro is WSL2:

```powershell
wsl -l -v
```

5. Start Docker Desktop before opening this repo in VS Code.

## Path A: Build and Test Without VS Code

### 1. Edit project files

- Code: `source/src/`
- Graphics: `source/graphics/`
- Audio: `source/audio/` and `source/dmg_audio/`

### 2. Build ROM (release)

```sh
make compile-butano CMD=make
```

### 3. ROM output

- Use this ROM in your emulator: `./<repo-folder-name>.gba`

### 4. Clean all generated files

```sh
make clean
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

These tasks auto-detect whether VS Code runs on host or inside the Dev Container.

### 3. Clean in VS Code

Use `Tasks: Run Task`:
- `Clean Outputs`
- `Clean Everything (including Docker stamps)`

### 4. Run or Debug on host emulator

In VS Code:
- `Run -> Start Debugging` (or `F5`) to debug
- `Run -> Run Without Debugging` to just run

Launch configs used:
- `Attach to mGBA GDB stub (host:2345)` for debugging
- `Run ROM on host emulator (no debugger)` for run-only

### 5. Choose host emulator (optional)

Default emulator is `mGBA` (auto-discovered).

To configure explicitly, copy `.emulator-bridge.env.example` to `.emulator-bridge.env`
and set `GBA_EMULATOR` / `GBA_EMULATOR_BIN`.

Examples:
- macOS mGBA: `GBA_EMULATOR_BIN=/Applications/mGBA.app/Contents/MacOS/mGBA`
- WSL2 + Windows mGBA install: `GBA_EMULATOR_BIN=/mnt/c/Program Files/mGBA/mGBA.exe`
- VisualBoyAdvance-M: set `GBA_EMULATOR=visualboyadvance-m`

Compatibility:
- `Run -> Run Without Debugging` uses launch config `Run ROM on host emulator (no debugger)`. It works with any supported emulator (for example `mGBA` or `visualboyadvance-m`).
- `Run -> Start Debugging` uses launch config `Attach to mGBA GDB stub (host:2345)`. This requires `mGBA` because GDB attach depends on the mGBA debug stub.

If host bridge is not reachable, run on host:

```sh
bash scripts/start_mgba_bridge.sh
```

When opening/reopening the Dev Container, the bridge is restarted automatically.

Windows PowerShell fallback (native Windows VS Code sessions):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start_mgba_bridge.ps1
```

Bridge log (host):

```sh
cat /tmp/mgba-host-bridge.log
```

## Notes

- Docker Desktop auto-start is supported on macOS and on WSL2 Ubuntu.
- Host emulator auto-discovery supports macOS, Linux, Windows, and WSL2 paths.
- Build directories are separated to avoid stale dependency conflicts:
  `build_dev_*` for devcontainer tasks, `build_host_*` for host-via-Docker tasks.
