#!/usr/bin/env python3
"""Host-side HTTP bridge to launch a configured GBA emulator from a devcontainer."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional


EMULATOR_ALIASES = {
    "mgba": "mgba",
    "mGBA": "mgba",
    "vbam": "visualboyadvance-m",
    "vba": "visualboyadvance-m",
    "visualboyadvance-m": "visualboyadvance-m",
    "visualboyadvance": "visualboyadvance-m",
}


def normalize_emulator(raw: Optional[str]) -> str:
    name = (raw or "mgba").strip()
    key = name.lower()
    normalized = EMULATOR_ALIASES.get(key)
    if normalized:
        return normalized
    raise ValueError(
        f"Unsupported emulator '{name}'. Supported values: mgba, visualboyadvance-m"
    )


def _append_if_exists(candidates: list[str], value: Optional[str]) -> None:
    if not value:
        return
    path = Path(value).expanduser()
    if path.is_file():
        candidates.append(str(path))


def _is_wsl() -> bool:
    release = platform.release().lower()
    if "microsoft" in release:
        return True
    try:
        return "microsoft" in Path("/proc/version").read_text(encoding="utf-8").lower()
    except OSError:
        return False


def _candidate_paths(emulator: str) -> tuple[list[str], list[str]]:
    candidates: list[str] = []
    path_bins: list[str] = []

    if emulator == "mgba":
        _append_if_exists(candidates, os.environ.get("GBA_EMULATOR_BIN"))
        _append_if_exists(candidates, os.environ.get("MGBA_BIN"))

        if platform.system() == "Darwin":
            _append_if_exists(candidates, "/Applications/mGBA.app/Contents/MacOS/mGBA")
        elif platform.system() == "Windows":
            _append_if_exists(
                candidates,
                str(Path(os.environ.get("ProgramFiles", "")) / "mGBA" / "mGBA.exe"),
            )
            _append_if_exists(
                candidates,
                str(Path(os.environ.get("ProgramFiles(x86)", "")) / "mGBA" / "mGBA.exe"),
            )
            _append_if_exists(
                candidates,
                str(Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "mGBA" / "mGBA.exe"),
            )
        else:
            _append_if_exists(candidates, "/usr/bin/mgba")
            _append_if_exists(candidates, "/usr/local/bin/mgba")
            if _is_wsl():
                _append_if_exists(candidates, "/mnt/c/Program Files/mGBA/mGBA.exe")
                _append_if_exists(candidates, "/mnt/c/Program Files (x86)/mGBA/mGBA.exe")

        path_bins = ["mgba", "mGBA"]

    elif emulator == "visualboyadvance-m":
        _append_if_exists(candidates, os.environ.get("GBA_EMULATOR_BIN"))
        _append_if_exists(candidates, os.environ.get("VBA_BIN"))
        _append_if_exists(candidates, os.environ.get("VBAM_BIN"))

        if platform.system() == "Darwin":
            _append_if_exists(
                candidates,
                "/Applications/visualboyadvance-m.app/Contents/MacOS/visualboyadvance-m",
            )
        elif platform.system() == "Windows":
            _append_if_exists(
                candidates,
                str(
                    Path(os.environ.get("ProgramFiles", ""))
                    / "VisualBoyAdvance-M"
                    / "visualboyadvance-m.exe"
                ),
            )
            _append_if_exists(
                candidates,
                str(
                    Path(os.environ.get("ProgramFiles(x86)", ""))
                    / "VisualBoyAdvance-M"
                    / "visualboyadvance-m.exe"
                ),
            )
        else:
            _append_if_exists(candidates, "/usr/bin/visualboyadvance-m")
            _append_if_exists(candidates, "/usr/local/bin/visualboyadvance-m")
            if _is_wsl():
                _append_if_exists(
                    candidates,
                    "/mnt/c/Program Files/VisualBoyAdvance-M/visualboyadvance-m.exe",
                )
                _append_if_exists(
                    candidates,
                    "/mnt/c/Program Files (x86)/VisualBoyAdvance-M/visualboyadvance-m.exe",
                )

        path_bins = ["visualboyadvance-m", "vbam"]

    return candidates, path_bins


def resolve_emulator_bin(emulator: str, explicit: Optional[str]) -> str:
    if explicit:
        explicit_path = Path(explicit).expanduser()
        if explicit_path.is_file():
            return str(explicit_path)
        raise FileNotFoundError(f"Emulator binary not found at: {explicit}")

    candidates, path_bins = _candidate_paths(emulator)

    for candidate in candidates:
        if Path(candidate).is_file():
            return candidate

    for bin_name in path_bins:
        in_path = shutil.which(bin_name)
        if in_path:
            return in_path

    if emulator == "mgba":
        hint = "Set GBA_EMULATOR_BIN (or MGBA_BIN) to your mGBA executable path."
    else:
        hint = (
            "Set GBA_EMULATOR_BIN (or VBA_BIN/VBAM_BIN) to your "
            "VisualBoyAdvance-M executable path."
        )

    raise FileNotFoundError(f"Could not find emulator binary for '{emulator}'. {hint}")


def build_launch_command(emulator: str, emulator_bin: str, rom_path: Path, debug: bool) -> list[str]:
    if emulator == "mgba":
        cmd = [emulator_bin, str(rom_path)]
        if debug:
            cmd.insert(1, "-g")
        return cmd

    if emulator == "visualboyadvance-m":
        if debug:
            raise RuntimeError(
                "Debug attach is only supported with mGBA. "
                "Use Run without Debugging, or set GBA_EMULATOR=mgba."
            )
        return [emulator_bin, str(rom_path)]

    raise RuntimeError(f"Unsupported emulator: {emulator}")


def parse_bool(value: object, default: bool = True) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in ("1", "true", "yes", "on"):
            return True
        if normalized in ("0", "false", "no", "off"):
            return False
    return default


class BridgeState:
    def __init__(self, emulator: str, emulator_bin: Optional[str], workspace_root: Path):
        self.default_emulator = normalize_emulator(emulator)
        self.default_emulator_bin = emulator_bin
        self.workspace_root = workspace_root
        self.process: Optional[subprocess.Popen] = None
        self.lock = threading.Lock()

    def launch(
        self,
        rom: str,
        debug: bool = True,
        emulator: Optional[str] = None,
        emulator_bin: Optional[str] = None,
    ) -> dict:
        with self.lock:
            rom_path = Path(rom)
            if not rom_path.is_absolute():
                rom_path = (self.workspace_root / rom_path).resolve()
            if not rom_path.is_file():
                raise FileNotFoundError(f"ROM not found: {rom}")

            selected_emulator = normalize_emulator(emulator or self.default_emulator)
            selected_emulator_bin = resolve_emulator_bin(
                selected_emulator,
                emulator_bin or self.default_emulator_bin,
            )

            if self.process is not None and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)

            cmd = build_launch_command(selected_emulator, selected_emulator_bin, rom_path, debug)
            self.process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return {
                "ok": True,
                "pid": self.process.pid,
                "cmd": cmd,
                "emulator": selected_emulator,
                "debug": debug,
            }

    def health_payload(self) -> dict:
        return {
            "ok": True,
            "emulator": self.default_emulator,
            "debug_attach_supported": self.default_emulator == "mgba",
        }


def make_handler(state: BridgeState):
    class Handler(BaseHTTPRequestHandler):
        def _send_json(self, status: int, payload: dict) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path == "/health":
                self._send_json(200, state.health_payload())
            else:
                self._send_json(404, {"ok": False, "error": "Not found"})

        def do_POST(self) -> None:
            if self.path == "/shutdown":
                self._send_json(200, {"ok": True, "message": "Shutting down"})
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return

            if self.path != "/launch":
                self._send_json(404, {"ok": False, "error": "Not found"})
                return

            try:
                length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(length)
                data = json.loads(raw.decode("utf-8")) if raw else {}
                rom = data.get("rom", "")
                if not rom:
                    raise ValueError("Missing 'rom' in request body")

                debug = parse_bool(data.get("debug"), default=True)
                emulator = data.get("emulator")
                emulator_bin = data.get("emulator_bin")

                result = state.launch(
                    rom=rom,
                    debug=debug,
                    emulator=emulator,
                    emulator_bin=emulator_bin,
                )
                self._send_json(200, result)
            except FileNotFoundError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
            except ValueError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
            except Exception as exc:  # noqa: BLE001
                self._send_json(500, {"ok": False, "error": str(exc)})

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description="Host bridge for launching a GBA emulator")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("GBA_BRIDGE_PORT", os.environ.get("MGBA_BRIDGE_PORT", "17777"))),
    )
    parser.add_argument("--emulator", default=os.environ.get("GBA_EMULATOR", "mgba"))
    parser.add_argument(
        "--emulator-bin",
        default=os.environ.get("GBA_EMULATOR_BIN", os.environ.get("MGBA_BIN")),
    )
    parser.add_argument("--mgba-bin", default=None, help=argparse.SUPPRESS)
    parser.add_argument(
        "--workspace-root",
        default=str(Path(__file__).resolve().parent.parent),
        help="Repository root used to resolve relative ROM paths",
    )
    args = parser.parse_args()

    if args.mgba_bin and not args.emulator_bin:
        args.emulator_bin = args.mgba_bin

    try:
        default_emulator = normalize_emulator(args.emulator)
    except ValueError as exc:
        print(f"Warning: {exc}. Falling back to 'mgba'.")
        default_emulator = "mgba"

    try:
        resolved = resolve_emulator_bin(default_emulator, args.emulator_bin)
    except FileNotFoundError as exc:
        print(f"Warning: {exc}")
        resolved = args.emulator_bin

    workspace_root = Path(args.workspace_root).resolve()
    state = BridgeState(default_emulator, resolved, workspace_root)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(state))

    print(
        "Host emulator bridge listening on "
        f"http://{args.host}:{args.port} "
        f"(default emulator: {default_emulator}, binary: {resolved or 'auto-detect'})"
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
