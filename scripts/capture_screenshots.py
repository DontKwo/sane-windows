"""Capture the desktop UI screenshot for Sane Windows using the compiled EXE."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

REPO_DIR = Path(__file__).resolve().parent.parent


def capture_screenshot(out_dir: Path, exe_path: Path) -> Path:
    """Capture 01_main.png from SaneWindows-Windows.exe --screenshot."""
    resolved_exe = exe_path.expanduser().resolve()
    if not resolved_exe.is_file():
        raise FileNotFoundError(f"Executable not found at {resolved_exe}; build it first.")
    resolved_out = out_dir.expanduser().resolve()
    resolved_out.mkdir(parents=True, exist_ok=True)
    target = resolved_out / "01_main.png"
    subprocess.run([str(resolved_exe), "--screenshot", str(target)], check=True, timeout=60)  # noqa: 32
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture Sane Windows UI screenshot.")
    parser.add_argument("--out-dir", type=Path, default=REPO_DIR / "assets" / "screenshots")
    parser.add_argument("--exe", type=Path, default=REPO_DIR / "build" / "SaneWindows-Windows.exe")
    args = parser.parse_args()
    target = capture_screenshot(args.out_dir, args.exe)
    sys.stdout.write(f"Saved screenshot to {target}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
