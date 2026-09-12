"""grid config for the backend build contract."""

from __future__ import annotations

import argparse
import shlex
import subprocess
from pathlib import Path

from build.config_model import BackendConfig

def _grid_config(config: Path, *args: str) -> str:
    """Ask grid-config a question; required settings must be available."""
    try:
        return subprocess.check_output([str(config), *args], text=True,
                                       stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, OSError) as exc:
        if args == ("--summary",):
            return ""
        raise RuntimeError(f"{config} {' '.join(args)} failed: {exc}") from exc


def configure_grid(prefix: Path, entry: dict, args: argparse.Namespace) -> BackendConfig:
    """Read Grid's build back out of its own grid-config script."""
    cfg = BackendConfig("grid", str(prefix))
    cfg.language = "cpp"

    config = Path(entry.get("config") or (prefix / "bin" / "grid-config"))
    if not config.exists():
        raise RuntimeError(
            f"Grid's build settings live in {config}, which does not exist.\n"
            f"Re-run './bootstrap --backend grid', or pass --grid-prefix=PATH."
        )

    cfg.passC.extend(shlex.split(_grid_config(config, "--cxxflags")))

    # Grid may give incorrect results without this; QEX's own Grid bindings
    # set it for the same reason.
    cfg.passC.append("-fno-strict-aliasing")
    # Nim declares a seq's backing array as data[1] and allocates more at
    # run time, which this otherwise reports as an out-of-bounds access.
    cfg.passC.append("-Wno-array-bounds")

    flags = shlex.split(_grid_config(config, "--ldflags")) + \
            shlex.split(_grid_config(config, "--libs"))
    cfg.passL.extend(flags)
    for index, token in enumerate(flags):
        if token == "-L" and index + 1 < len(flags):
            cfg.passL.append(f"-Wl,-rpath,{flags[index + 1]}")
        elif token.startswith("-L") and len(token) > 2:
            cfg.passL.append(f"-Wl,-rpath,{token[2:]}")

    summary = _grid_config(config, "--summary")
    for line in summary.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].upper().startswith("SIMD"):
            cfg.note("simd", parts[-1])

    cfg.note("config", str(config))
    cfg.note("accelerator", entry.get("accelerator", ""))
    return cfg
