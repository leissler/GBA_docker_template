#!/usr/bin/env python3
"""Small host-side HTTP bridge to launch mGBA for devcontainer debugging."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional


class BridgeState:
    def __init__(self, mgba_bin: Optional[str], workspace_root: Path):
        self.mgba_bin = mgba_bin
        self.workspace_root = workspace_root
        self.process: Optional[subprocess.Popen] = None
        self.lock = threading.Lock()

    def launch(self, rom: str, debug: bool = True) -> dict:
        with self.lock:
            rom_path = Path(rom)
            if not rom_path.is_absolute():
                rom_path = (self.workspace_root / rom_path).resolve()
            if not rom_path.is_file():
                raise FileNotFoundError(f"ROM not found: {rom}")

            mgba_bin = self.mgba_bin or resolve_mgba_bin(None)

            if self.process is not None and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)

            cmd = [mgba_bin, str(rom_path)]
            if debug:
                cmd.insert(1, "-g")
            self.process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return {"ok": True, "pid": self.process.pid, "cmd": cmd}


def resolve_mgba_bin(explicit: Optional[str]) -> str:
    if explicit:
        candidate = explicit
    else:
        candidate = os.environ.get("MGBA_BIN") or ""

    if candidate:
        if Path(candidate).is_file():
            return candidate
        raise FileNotFoundError(f"mGBA binary not found at: {candidate}")

    mac_default = "/Applications/mGBA.app/Contents/MacOS/mGBA"
    if Path(mac_default).is_file():
        return mac_default

    in_path = shutil.which("mgba")
    if in_path:
        return in_path

    raise FileNotFoundError(
        "Could not find mGBA binary. Set MGBA_BIN or pass --mgba-bin."
    )


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
                self._send_json(200, {"ok": True})
            else:
                self._send_json(404, {"ok": False, "error": "Not found"})

        def do_POST(self) -> None:
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

                debug = bool(data.get("debug", True))
                result = state.launch(rom, debug=debug)
                self._send_json(200, result)
            except FileNotFoundError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
            except Exception as exc:  # noqa: BLE001
                self._send_json(500, {"ok": False, "error": str(exc)})

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description="Host bridge for launching mGBA")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.environ.get("MGBA_BRIDGE_PORT", "17777")))
    parser.add_argument("--mgba-bin", default=None)
    parser.add_argument(
        "--workspace-root",
        default=str(Path(__file__).resolve().parent.parent),
        help="Repository root used to resolve relative ROM paths",
    )
    args = parser.parse_args()

    try:
        mgba_bin = resolve_mgba_bin(args.mgba_bin)
    except FileNotFoundError as exc:
        # Keep the bridge alive so health checks pass; launch will return a clear error.
        print(f"Warning: {exc}")
        mgba_bin = None
    workspace_root = Path(args.workspace_root).resolve()
    state = BridgeState(mgba_bin, workspace_root)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(state))

    print(f"mGBA bridge listening on http://{args.host}:{args.port} using {mgba_bin}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
