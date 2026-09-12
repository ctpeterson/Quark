"""
quda.py — download, build, and install QUDA and its dependencies.

build: build/quda.py
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

Usage
-----
    python3 build/quda.py [OPTIONS]

Normally invoked through the top-level ``bootstrap`` driver:

    ./bootstrap --backend quda [OPTIONS]

Run with ``--help`` for the full list of flags. Everything lands under the
prefix described in ``common.py``:

    <prefix>/deps/quda      QMP and QIO, when QUDA is built with them
    <prefix>/nim            Nim toolchain
    <prefix>/quda           QUDA install prefix
    <prefix>/src/quda       QUDA source checkout
    <prefix>/src/quda-build out-of-source CMake build tree

QUDA is built with CMake rather than autotools, so there is no config script
to read back the way Grid has ``grid-config``. What a build decided is instead
recorded in ``<build>/CMakeCache.txt``, and the essentials are copied into the
bootstrap manifest for `configure` to read.

The source checkout is deliberately kept after installation. QEX's QUDA
bindings include headers from QUDA's ``tests/utils`` directory, which is not
installed, so a QEX build against QUDA needs the source tree to still be there.

MIT License

Copyright (c) 2026 Curtis Taylor Peterson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

from __future__ import annotations

import argparse
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from build.common import (  # noqa: E402
    clone_repository,
    Layout, StageTracker, add_common_arguments, ensure_compiler, ensure_dir,
    resolve_nim, run, warn, which, write_manifest,
)

BACKEND = "quda"

# QUDA's own defaults, repeated here so that a setting is only passed to CMake
# when the user actually chose it and QUDA's defaults otherwise stand.
DEFAULT_GPU_ARCH = {"cuda": "sm_80", "hip": "gfx90a", "sycl": ""}

# Booleans QUDA exposes as plain ON/OFF CMake options. Each becomes a pair of
# --enable-X / --disable-X flags, with no default, so an unset option leaves
# QUDA's own default in place.
BOOLEAN_OPTIONS: list[tuple[str, str, str]] = [
    # (flag name,           CMake variable,           help)
    ("multigrid",           "QUDA_MULTIGRID",         "multigrid solvers"),
    ("mpi",                 "QUDA_MPI",               "MPI communications"),
    ("qmp",                 "QUDA_QMP",               "QMP communications"),
    ("qio",                 "QUDA_QIO",               "QIO lattice I/O"),
    ("openmp",              "QUDA_OPENMP",            "OpenMP in host code"),
    ("shared",              "QUDA_BUILD_SHAREDLIB",   "a shared library rather than static"),
    ("dirac-wilson",        "QUDA_DIRAC_WILSON",      "the Wilson Dirac operator"),
    ("dirac-clover",        "QUDA_DIRAC_CLOVER",      "the clover Dirac operator"),
    ("dirac-domain-wall",   "QUDA_DIRAC_DOMAIN_WALL", "the domain wall Dirac operator"),
    ("dirac-staggered",     "QUDA_DIRAC_STAGGERED",   "the staggered Dirac operator"),
    ("dirac-twisted-mass",  "QUDA_DIRAC_TWISTED_MASS", "the twisted mass Dirac operator"),
    ("dirac-twisted-clover", "QUDA_DIRAC_TWISTED_CLOVER", "the twisted clover Dirac operator"),
    ("dirac-clover-hasenbusch", "QUDA_DIRAC_CLOVER_HASENBUSCH",
     "the Hasenbusch-twisted clover Dirac operator"),
    ("dirac-laplace",       "QUDA_DIRAC_LAPLACE",     "the Laplace operator"),
    ("dirac-covdev",        "QUDA_DIRAC_COVDEV",      "the covariant derivative"),
    ("interface-milc",      "QUDA_INTERFACE_MILC",    "the MILC interface"),
    ("interface-qdp",       "QUDA_INTERFACE_QDP",     "the QDP interface"),
    ("interface-cps",       "QUDA_INTERFACE_CPS",     "the CPS interface"),
    ("interface-bqcd",      "QUDA_INTERFACE_BQCD",    "the BQCD interface"),
    ("interface-tifr",      "QUDA_INTERFACE_TIFR",    "the TIFR interface"),
    ("interface-all",       "QUDA_INTERFACE_ALL",     "every host interface"),
    ("blocksolver",         "QUDA_BLOCKSOLVER",       "block solvers"),
    ("arpack",              "QUDA_ARPACK",            "ARPACK eigensolvers"),
    ("openblas",            "QUDA_OPENBLAS",          "OpenBLAS"),
    ("backwards",           "QUDA_BACKWARDS",         "the backward-cpp stack tracer"),
    ("build-all-tests",     "QUDA_BUILD_ALL_TESTS",   "QUDA's full test suite"),
    ("install-all-tests",   "QUDA_INSTALL_ALL_TESTS", "installing QUDA's tests"),
    ("download-usqcd",      "QUDA_DOWNLOAD_USQCD",    "QUDA downloading QMP and QIO itself"),
    ("download-eigen",      "QUDA_DOWNLOAD_EIGEN",    "QUDA downloading Eigen itself"),
    ("download-arpack",     "QUDA_DOWNLOAD_ARPACK",   "QUDA downloading ARPACK itself"),
    ("download-openblas",   "QUDA_DOWNLOAD_OPENBLAS", "QUDA downloading OpenBLAS itself"),
    ("fast-compile-dslash", "QUDA_FAST_COMPILE_DSLASH",
     "fast, slow-running dslash kernels, for development builds"),
    ("fast-compile-reduce", "QUDA_FAST_COMPILE_REDUCE",
     "fast, slow-running reduction kernels, for development builds"),
]


# ──────────────────────────────────────────────────────────────────────
# QUDA builder
# ──────────────────────────────────────────────────────────────────────

def clone_quda(args: argparse.Namespace, layout: Layout) -> Path:
    """Clone or update the QUDA source checkout. Returns the source directory."""
    quda_src = layout.src / "quda"
    clone_repository(quda_src, args.quda_repo, args.quda_branch, update=args.quda_pull)
    return quda_src


def _cmake_flags(args: argparse.Namespace, layout: Layout, quda_src: Path) -> list[str]:
    """Assemble QUDA's CMake arguments from the parsed options."""
    flags = [
        f"-DCMAKE_INSTALL_PREFIX={layout.prefix}",
        f"-DCMAKE_BUILD_TYPE={args.build_type}",
        f"-DQUDA_TARGET_TYPE={args.target.upper()}",
    ]

    # ── GPU architecture ────────────────────────────────────────────
    arch = args.gpu_arch or DEFAULT_GPU_ARCH.get(args.target, "")
    if arch:
        flags.append(f"-DQUDA_GPU_ARCH={arch}")

    # ── Booleans, only when the user chose one ──────────────────────
    for flag_name, cmake_var, _help in BOOLEAN_OPTIONS:
        value = getattr(args, flag_name.replace("-", "_"))
        if value is not None:
            flags.append(f"-D{cmake_var}={'ON' if value else 'OFF'}")

    # ── Instantiation bitmasks and sizes ────────────────────────────
    if args.precision is not None:
        flags.append(f"-DQUDA_PRECISION={args.precision}")
    if args.reconstruct is not None:
        flags.append(f"-DQUDA_RECONSTRUCT={args.reconstruct}")
    if args.max_multi_blas_n is not None:
        flags.append(f"-DQUDA_MAX_MULTI_BLAS_N={args.max_multi_blas_n}")
    if args.cxx_standard is not None:
        flags.append(f"-DQUDA_CXX_STANDARD={args.cxx_standard}")

    # ── Dependency locations ────────────────────────────────────────
    # QUDA can download QMP and QIO itself; when it is pointed at ones that
    # already exist, they go in this backend's own dependency prefix.
    if args.qmpdir: flags.append(f"-DQMP_DIR={args.qmpdir}")
    if args.qiodir: flags.append(f"-DQIO_DIR={args.qiodir}")
    if args.arpack_home: flags.append(f"-DQUDA_ARPACK_HOME={args.arpack_home}")
    if args.openblas_home: flags.append(f"-DQUDA_OPENBLAS_HOME={args.openblas_home}")

    # ── Compiler overrides ──────────────────────────────────────────
    if args.cc: flags.append(f"-DCMAKE_C_COMPILER={args.cc}")
    if args.cxx: flags.append(f"-DCMAKE_CXX_COMPILER={args.cxx}")
    if args.cuda_dir: flags.append(f"-DCUDAToolkit_ROOT={args.cuda_dir}")

    # ── Raw -D defines and extra flags, passed through verbatim ─────
    for define in args.cmake_define or []:
        flags.append(f"-D{define}")
    if args.extra_cmake_flags:
        flags.extend(shlex.split(args.extra_cmake_flags))

    return flags


def build_quda(args: argparse.Namespace, layout: Layout, quda_src: Path) -> Path:
    """Configure, build, and install QUDA. Returns the install prefix."""
    if not which("cmake"):
        raise RuntimeError(
            "QUDA is built with CMake, and no 'cmake' was found on PATH.\n"
            "Install CMake 3.18 or later and try again."
        )

    build_dir = ensure_dir(layout.src / "quda-build")
    run(["cmake", "-S", str(quda_src), "-B", str(build_dir)]
        + _cmake_flags(args, layout, quda_src))
    run(["cmake", "--build", str(build_dir), f"-j{args.jobs}"])
    run(["cmake", "--install", str(build_dir)])
    return layout.prefix


def _cache_value(build_dir: Path, key: str) -> str:
    """Read one value back out of a CMake cache.

    QUDA has no generated config script, so the cache is the only record of
    what a build actually decided once defaults and dependency detection have
    had their say.
    """
    cache = build_dir / "CMakeCache.txt"
    if not cache.exists(): return ""
    prefix = f"{key}:"
    for line in cache.read_text().splitlines():
        if line.startswith(prefix):
            return line.split("=", 1)[1] if "=" in line else ""
    return ""


# ──────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────

EPILOG = """\
examples:
  # NVIDIA GPU build for Ampere, with multigrid
  ./bootstrap --backend quda --gpu-arch sm_80 --enable-multigrid

  # AMD GPU build
  ./bootstrap --backend quda --target hip --gpu-arch gfx90a

  # Intel GPU build
  ./bootstrap --backend quda --target sycl

  # Staggered-only build with MPI through QMP and QIO, downloaded by QUDA
  ./bootstrap --backend quda --enable-dirac-staggered --disable-dirac-wilson \\
      --enable-qmp --enable-qio --enable-download-usqcd

  # Development build with fast-compiling kernels
  ./bootstrap --backend quda --build-type DEVEL \\
      --enable-fast-compile-dslash --enable-fast-compile-reduce

  # A QEX that solves through this QUDA
  ./bootstrap --backend quda --gpu-arch sm_80 --backend qex --with-quda

  # Anything not exposed above
  ./bootstrap --backend quda --cmake-define QUDA_MAX_MULTI_RHS_TILE=8
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="bootstrap quda",
        description="Bootstrap QUDA and all of its dependencies for Quark.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=EPILOG,
    )

    add_common_arguments(p)

    # ── Target and architecture ─────────────────────────────────────
    tgt = p.add_argument_group("target / GPU")
    tgt.add_argument("--target", default="cuda", choices=["cuda", "hip", "sycl"],
                     help="QUDA compilation target (default: cuda)")
    tgt.add_argument("--gpu-arch", default=None, metavar="ARCH",
                     help="GPU architecture: sm_60/sm_70/sm_80/sm_90 for CUDA, "
                          "gfx906/gfx908/gfx90a for HIP "
                          "(default: sm_80 for CUDA, gfx90a for HIP)")
    tgt.add_argument("--cuda-dir", default=None, metavar="PREFIX",
                     help="CUDA toolkit prefix, if it is not found automatically")

    # ── Build type ──────────────────────────────────────────────────
    bt = p.add_argument_group("build type")
    bt.add_argument("--build-type", default="RELEASE",
                    choices=["RELEASE", "DEVEL", "DEBUG", "HOSTDEBUG", "SANITIZE"],
                    help="CMake build type (default: RELEASE)")
    bt.add_argument("--cxx-standard", default=None, type=int, metavar="N",
                    help="C++ standard QUDA is compiled with")

    # ── Feature switches ────────────────────────────────────────────
    feat = p.add_argument_group(
        "features",
        "Each option leaves QUDA's own default in place unless given.")
    for flag_name, cmake_var, help_text in BOOLEAN_OPTIONS:
        dest = flag_name.replace("-", "_")
        # A paired store_true/store_false rather than BooleanOptionalAction:
        # that action derives its own negative form from the first option
        # string, so an explicit '--disable-X' would be read as another way of
        # saying true. Two arguments sharing one dest keeps both meanings.
        feat.add_argument(f"--enable-{flag_name}", dest=dest, default=None,
                          action="store_true",
                          help=f"Enable {help_text} ({cmake_var})")
        feat.add_argument(f"--disable-{flag_name}", dest=dest,
                          action="store_false", help=argparse.SUPPRESS)

    # ── Instantiation ───────────────────────────────────────────────
    inst = p.add_argument_group("instantiation")
    inst.add_argument("--precision", default=None, metavar="MASK",
                      help="Which precisions to instantiate, a 4-bit mask over "
                           "double, single, half, quarter (QUDA default: 14)")
    inst.add_argument("--reconstruct", default=None, metavar="MASK",
                      help="Which gauge reconstructs to instantiate, a 3-bit mask "
                           "over 18, 13/12, 9/8 (QUDA default: 7)")
    inst.add_argument("--max-multi-blas-n", default=None, type=int, metavar="N",
                      help="Maximum multi-blas N QUDA instantiates")

    # ── Dependency locations ────────────────────────────────────────
    dep = p.add_argument_group("dependency locations")
    dep.add_argument("--qmpdir", metavar="PREFIX", help="Existing QMP install prefix")
    dep.add_argument("--qiodir", metavar="PREFIX", help="Existing QIO install prefix")
    dep.add_argument("--arpack-home", metavar="PREFIX", help="Existing ARPACK prefix")
    dep.add_argument("--openblas-home", metavar="PREFIX", help="Existing OpenBLAS prefix")

    # ── Compiler overrides ──────────────────────────────────────────
    comp = p.add_argument_group("compiler overrides")
    comp.add_argument("--cc", metavar="COMPILER", help="C compiler")
    comp.add_argument("--cxx", metavar="COMPILER", help="C++ compiler")

    # ── Source control ──────────────────────────────────────────────
    srcgrp = p.add_argument_group("source control")
    srcgrp.add_argument("--quda-repo", default="https://github.com/lattice/quda.git",
                        metavar="URL",
                        help="QUDA git repository to clone "
                             "(default: https://github.com/lattice/quda.git)")
    srcgrp.add_argument("--quda-branch", default="develop", metavar="BRANCH",
                        help="QUDA git branch to clone (default: develop)")
    srcgrp.add_argument("--quda-pull", action="store_true",
                        help="Run git pull in an existing QUDA checkout")

    # ── Escape hatches ──────────────────────────────────────────────
    p.add_argument("--cmake-define", action="append", metavar="VAR=VALUE",
                   help="Extra CMake define, without the leading -D. Repeatable.")
    p.add_argument("--extra-cmake-flags", metavar="'FLAGS'",
                   help="Raw string appended verbatim to the cmake invocation")

    return p


# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────

def _stage_list(args: argparse.Namespace) -> list[tuple[str, str]]:
    stages: list[tuple[str, str]] = []
    if not args.skip_nim:
        stages.append(("nim", "Installing Nim"))
    stages.append(("quda", "Building QUDA"))
    return stages


def bootstrap(args: argparse.Namespace, layout: Layout, cc: str, cxx: str) -> None:
    """Install QUDA into *layout*.

    QUDA has no dependency stage of its own: CMake finds the CUDA, HIP, or
    SYCL toolkit already on the machine, and downloads Eigen and, on request,
    QMP and QIO by itself.
    """
    stages = StageTracker(BACKEND, _stage_list(args))

    if args.skip_deps:
        print("--skip-deps: QUDA resolves its dependencies through CMake, "
              "so there is nothing to skip")

    if not args.skip_nim:
        stages.begin("nim")
    nim = resolve_nim(layout, skip=args.skip_nim, version=args.nim_version)

    stages.begin("quda")
    quda_src = clone_quda(args, layout)
    prefix = build_quda(args, layout, quda_src)
    build_dir = layout.src / "quda-build"

    test_utils = quda_src / "tests" / "utils"
    if not test_utils.exists():
        warn(f"QUDA installed but {test_utils} is missing.\n"
             f"QEX's QUDA bindings include headers from that directory, so a "
             f"QEX build against this QUDA will fail without it.")

    write_manifest(layout, BACKEND, {
        "prefix": str(prefix),
        "config": "",  # QUDA generates no config script; see 'cache' below
        "cache": str(build_dir / "CMakeCache.txt"),
        "source": str(quda_src),
        "testUtils": str(test_utils),
        "repo": args.quda_repo,
        "branch": args.quda_branch,
        "target": args.target.upper(),
        "gpuArch": _cache_value(build_dir, "QUDA_GPU_ARCH")
                   or args.gpu_arch or DEFAULT_GPU_ARCH.get(args.target, ""),
        "buildType": args.build_type,
        "multigrid": _cache_value(build_dir, "QUDA_MULTIGRID"),
        "mpi": _cache_value(build_dir, "QUDA_MPI"),
        "qmp": _cache_value(build_dir, "QUDA_QMP"),
        "qio": _cache_value(build_dir, "QUDA_QIO"),
        "cc": args.cc or cc,
        "cxx": args.cxx or cxx,
        "nim": str(nim),
    }, nim=nim)

    stages.finish()
    print(f"\n{'=' * 66}")
    print(f"QUDA installed to: {prefix}")
    print(f"Build settings:    {build_dir / 'CMakeCache.txt'}")
    print(f"Next step:         ./configure")
    print(f"{'=' * 66}\n")


def main() -> None:
    args = build_parser().parse_args()
    layout = Layout(Path(args.prefix), BACKEND)
    layout.create()
    cc, cxx = ensure_compiler(layout, no_llvm=args.no_llvm, jobs=args.jobs)
    print(f"Using CC={cc}  CXX={cxx}")
    bootstrap(args, layout, cc, cxx)


if __name__ == "__main__":
    main()
