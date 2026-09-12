"""quda config for the backend build contract."""

from __future__ import annotations

import argparse
from pathlib import Path

from build.config_model import BackendConfig

def read_cmake_cache(path: Path) -> dict[str, str]:
    """Read a CMake cache into a plain mapping of variable to value."""
    settings: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", "//")) or "=" not in line:
            continue
        name, _, value = line.partition("=")
        if ":" in name:
            name = name.split(":", 1)[0]
        settings[name.strip()] = value.strip()
    return settings


def configure_quda(prefix: Path, entry: dict, args: argparse.Namespace) -> BackendConfig:
    """Read QUDA's build back out of the CMake cache that produced it."""
    cfg = BackendConfig("quda", str(prefix))
    cfg.language = "cpp"

    include = prefix / "include"
    if not include.exists():
        raise RuntimeError(
            f"QUDA's headers were expected in {include}, which does not exist.\n"
            f"Re-run './bootstrap --backend quda', or pass --quda-prefix=PATH."
        )
    cfg.passC.append(f"-I{include}")

    for candidate in ("lib64", "lib"):
        libdir = prefix / candidate
        if libdir.exists():
            cfg.add_library_path(str(libdir))
            break
    cfg.passL.append("-lquda")
    cfg.nimFlags.append(f"-d:qudaDir={prefix}")

    # QEX's QUDA bindings include headers QUDA does not install, so the
    # source checkout has to stay reachable.
    test_utils = entry.get("testUtils", "")
    if test_utils:
        cfg.nimFlags.append(f"-d:qudaTestUtilsDir={test_utils}")
        cfg.note("testUtils", test_utils)

    cuda_lib_dir = args.cuda_lib_dir or _cuda_lib_dir_from_cache(entry)
    if cuda_lib_dir:
        cfg.passC.append(f"-I{Path(cuda_lib_dir).parent / 'include'}")
        cfg.add_library_path(cuda_lib_dir)
        cfg.passL.extend(["-lcudart", "-lcublas", "-lcufft"])
        cfg.nimFlags.append(f"-d:cudaLibDir={cuda_lib_dir}")
        cfg.note("cudaLibDir", cuda_lib_dir)

    cache = Path(entry.get("cache", ""))
    if cache.is_file():
        settings = read_cmake_cache(cache)
        cfg.note("cache", str(cache))
        for key, name in (("QUDA_TARGET_TYPE", "target"),
                          ("QUDA_GPU_ARCH", "gpuArch"),
                          ("QUDA_MULTIGRID", "multigrid"),
                          ("QUDA_MPI", "mpi"),
                          ("QUDA_QMP", "qmp"),
                          ("QUDA_QIO", "qio")):
            cfg.note(name, settings.get(key, ""))
    else:
        for name in ("target", "gpuArch", "multigrid", "mpi", "qmp", "qio"):
            cfg.note(name, entry.get(name, ""))
    return cfg


def _cuda_lib_dir_from_cache(entry: dict) -> str:
    """Find the CUDA library directory a QUDA build used, if it recorded one."""
    cache = Path(entry.get("cache", ""))
    if not cache.is_file(): return ""
    settings = read_cmake_cache(cache)
    for key in ("CUDAToolkit_LIBRARY_DIR", "CUDA_CUDART"):
        value = settings.get(key, "")
        if value:
            path = Path(value)
            return str(path if path.is_dir() else path.parent)
    root = settings.get("CUDAToolkit_LIBRARY_ROOT", "") or \
           settings.get("CUDAToolkit_ROOT", "")
    if root:
        for candidate in ("lib64", "lib"):
            directory = Path(root) / candidate
            if directory.exists(): return str(directory)
    return ""
