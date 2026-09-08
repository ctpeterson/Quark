"""
qex.py — download, build, and configure QEX and its dependencies.

build: build/qex.py
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

Usage
-----
    python3 build/qex.py [OPTIONS]

Normally invoked through the top-level ``bootstrap`` driver:

    ./bootstrap qex [OPTIONS]

Run with ``--help`` for the full list of flags. Everything lands under the
prefix described in ``common.py``:

    <prefix>/deps/qex       QMP and QIO
    <prefix>/nim            Nim toolchain
    <prefix>/qex            QEX build directory (qexconfig.nims, Makefile)
    <prefix>/src/qex        QEX source checkout

QEX is a Nim framework rather than a compiled library, so "installing" it
means checking out the source, building the C libraries it links against,
and running QEX's own ``configure`` in a build directory. That build
directory holds ``qexconfig.nims``, which records every compiler, SIMD, and
library setting QEX was configured with. It is QEX's counterpart to Grid's
``grid-config``, and Quark's `configure` reads it back rather than
re-deriving any of those settings.

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
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from build.common import (  # noqa: E402
    Layout, StageTracker, add_common_arguments, build_or_spack, download,
    ensure_compiler, ensure_dir, ensure_spack, lib_installed, resolve_nim,
    run, warn, write_manifest,
)

BACKEND = "qex"

QMP_VERSION = "2.5.4"
QIO_VERSION = "3.0.0"
USQCD_DOWNLOADS = "https://usqcd-software.github.io/downloads"

# QEX builds its C dependencies as position-independent static libraries so
# that Nim can link them into either a C or a C++ program.
USQCD_CFLAGS = "-Wall -O3 -std=gnu99 -g -fPIC"

# QEX selects its accelerator backend with the compile-time define
# '-d:Backend=...', read by src/backend/accelbase.nim. Note the capital B:
# it is a different define from Quark's own lowercase '-d:backend=...', which
# chooses which adapter Quark lowers through.
QEX_BACKENDS = {
    "none":   "CPU",
    "cpu":    "CPU",
    "cuda":   "CUDA",
    "hip":    "HIP",
    "sycl":   "SYCL",
    "openmp": "OpenMP",
}

# QEX compiles CUDA through a wrapper script in its own tree that drives nvcc
# and forwards host-only flags via -Xcompiler. The wrapper reads these three
# environment variables at compile time.
CCWRAPPER = "src/backend/util/ccwrapper"


# ──────────────────────────────────────────────────────────────────────
# Dependency builders
# ──────────────────────────────────────────────────────────────────────

def build_qmp(layout: Layout, cc: str, comms: str, jobs: str) -> None:
    """Build QMP, the USQCD message-passing layer QEX communicates through."""
    if lib_installed(layout.deps, "libqmp"):
        print("QMP already installed, skipping.")
        return
    src = layout.source("qmp")
    stem = f"qmp-{QMP_VERSION}"
    tarball = f"{stem}.tar.gz"
    if not (src / tarball).exists():
        download(f"{USQCD_DOWNLOADS}/qmp/{tarball}", src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / stem
    run([str(build_dir / "configure"),
         f"--prefix={layout.deps}",
         f"--with-qmp-comms-type={comms}",
         f"CC={cc}",
         f"CFLAGS={USQCD_CFLAGS}"], cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)


def build_qio(layout: Layout, cc: str, qmp_prefix: Path, jobs: str) -> None:
    """Build QIO, the USQCD lattice I/O layer. QIO bundles its own c-lime."""
    if lib_installed(layout.deps, "libqio"):
        print("QIO already installed, skipping.")
        return
    src = layout.source("qio")
    stem = f"qio-{QIO_VERSION}"
    tarball = f"{stem}.tar.gz"
    if not (src / tarball).exists():
        download(f"{USQCD_DOWNLOADS}/qio/{tarball}", src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / stem
    run([str(build_dir / "configure"),
         f"--prefix={layout.deps}",
         f"--with-qmp={qmp_prefix}",
         f"CC={cc}",
         f"CFLAGS={USQCD_CFLAGS}"], cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)


# ──────────────────────────────────────────────────────────────────────
# QEX builder
# ──────────────────────────────────────────────────────────────────────

def clone_qex(args: argparse.Namespace, layout: Layout) -> Path:
    """Clone or update the QEX source checkout. Returns the source directory."""
    qex_src = layout.src / "qex"
    if not qex_src.exists():
        run(f"git clone --branch {args.qex_branch} {args.qex_repo} {qex_src}")
    elif args.qex_pull:
        run("git pull", cwd=qex_src)
    return qex_src


def _grid_dir(args: argparse.Namespace, layout: Layout) -> str:
    """Return the Grid install prefix QEX should build against, if any.

    ``--with-grid`` without a value means the Grid this same prefix already
    bootstrapped, which is the common case: bootstrap Grid, then bootstrap a
    QEX that uses it.
    """
    if args.griddir: return args.griddir
    if args.with_grid is None: return ""
    prefix = Path(args.with_grid) if args.with_grid else layout.root / "grid"
    if not (prefix / "bin" / "grid-config").exists():
        raise RuntimeError(
            f"--with-grid needs a Grid install prefix containing bin/grid-config; "
            f"{prefix} has none.\n"
            f"Bootstrap Grid first with './bootstrap --backend grid', or pass "
            f"--with-grid=PREFIX."
        )
    return str(prefix)


def _quda_dir(args: argparse.Namespace, layout: Layout) -> str:
    """Return the QUDA install prefix QEX should build against, if any."""
    if args.qudadir: return args.qudadir
    if args.with_quda is None: return ""
    prefix = Path(args.with_quda) if args.with_quda else layout.root / "quda"
    if not (prefix / "include").exists():
        raise RuntimeError(
            f"--with-quda needs a QUDA install prefix containing include/; "
            f"{prefix} has none.\n"
            f"Bootstrap QUDA first with './bootstrap --backend quda', or pass "
            f"--with-quda=PREFIX."
        )
    return str(prefix)


def _cuda_lib_dir(args: argparse.Namespace) -> str:
    """Return the CUDA library directory, which QEX's QUDA bindings require.

    QEX derives its CUDA include path from this directory as ``../include``,
    so it must be the real library directory inside the CUDA toolkit.
    """
    if args.cudalibdir: return args.cudalibdir
    needs_cuda = args.with_quda is not None or args.qudadir
    if not needs_cuda: return ""
    for candidate in ("lib64", "lib"):
        d = Path(args.cuda_dir) / candidate
        if d.exists(): return str(d)
    raise RuntimeError(
        f"A QUDA build needs the CUDA library directory, and neither "
        f"{args.cuda_dir}/lib64 nor {args.cuda_dir}/lib exists.\n"
        f"Pass --cuda-dir=PREFIX or --cudalibdir=DIR."
    )


def _language(args: argparse.Namespace) -> str:
    """Return QEX's default language backend, 'cc' or 'cpp'.

    Grid, QUDA, Chroma, and every GPU backend but plain OpenMP are C++, so
    those builds must default to C++ whatever the user asked for. Choosing
    C for them produces link failures far from their cause, so the choice is
    made here rather than left to the user to remember.
    """
    if args.lang: return args.lang
    if args.accelerator in ("cuda", "hip", "sycl"): return "cpp"
    if args.with_grid is not None or args.griddir: return "cpp"
    if args.with_quda is not None or args.qudadir: return "cpp"
    if args.chromadir: return "cpp"
    return ""  # leave QEX's own default alone


def _accelerator_settings(
    args: argparse.Namespace, qex_src: Path,
) -> tuple[str, list[str], list[str]]:
    """Resolve the compiler, environment, and Nim defines for the GPU backend.

    Returns ``(cc, envs, nimargs)``. QEX selects its accelerator backend with
    '-d:Backend=...', and each backend needs a compiler that understands its
    kernels:

    CUDA    QEX's own ccwrapper, which drives nvcc with the host compiler and
            GPU architecture taken from the environment
    HIP     hipcc
    SYCL    a SYCL compiler such as icpx; QEX supplies -fsycl itself
    OpenMP  the ordinary host compiler, with OpenMP offload flags
    """
    backend = QEX_BACKENDS[args.accelerator]
    envs: list[str] = []
    nimargs: list[str] = []
    cc = args.cc or ""

    if backend == "CPU":
        return cc, envs, nimargs

    nimargs.append(f"-d:Backend={backend}")

    if backend == "CUDA":
        wrapper = qex_src / CCWRAPPER
        if not wrapper.exists():
            raise RuntimeError(f"QEX's CUDA compiler wrapper is missing: {wrapper}")
        # The wrapper is the compiler; nvcc, the host compiler, and the GPU
        # architecture reach it through the environment, as it expects.
        cc = cc or str(wrapper)
        nvcc = args.nvcc or str(Path(args.cuda_dir) / "bin" / "nvcc")
        envs += [
            f"CUDANVCC={nvcc}",
            f"CUDACCBIN={args.cuda_host_compiler}",
            f"CUDAARCH={args.cuda_arch}",
        ]
    elif backend == "HIP":
        cc = cc or "hipcc"
    elif backend == "SYCL":
        cc = cc or "icpx"
    elif backend == "OpenMP":
        # Offload target selection is compiler specific, so it is passed
        # through rather than guessed at.
        pass

    return cc, envs, nimargs


def _configure_settings(args: argparse.Namespace, layout: Layout,
                        qex_src: Path) -> list[str]:
    """Assemble QEX's ``key:value`` configure arguments from the parsed options.

    QEX's configure accepts any variable named in its ``configDefault.nims``
    and substitutes it into the generated ``qexconfig.nims``. Only settings the
    user actually chose are passed, so QEX's own defaults survive untouched.
    """
    settings: list[str] = [
        f"qmpDir:{args.qmpdir or layout.deps}",
        f"qioDir:{args.qiodir or layout.deps}",
    ]

    def add(key: str, value) -> None:
        if value is not None and value != "":
            settings.append(f"{key}:{value}")

    accel = QEX_BACKENDS[args.accelerator]
    cc, envs, nimargs = _accelerator_settings(args, qex_src)

    # ── Compilers and flags ─────────────────────────────────────────
    add("ccType", args.cctype)
    add("ccDef", _language(args))
    add("cc", cc)
    add("cflagsAlways", args.cflags_always)
    add("cflagsDebug", args.cflags_debug)
    add("cflagsSpeed", args.cflags_speed)
    add("ld", args.ld)
    add("ldflags", args.ldflags)
    add("cpp", args.cpp)
    add("cppflagsAlways", args.cppflags_always)
    add("cppflagsDebug", args.cppflags_debug)
    add("cppflagsSpeed", args.cppflags_speed)
    add("ldpp", args.ldpp)
    add("ldppflags", args.ldppflags)

    # ── SIMD ────────────────────────────────────────────────────────
    if args.simd is not None: settings.append(f"simd:{args.simd}")
    add("vlen", args.vlen)

    # ── Optional libraries ──────────────────────────────────────────
    # QEX reads Grid's own grid-config out of gridDir at compile time, and
    # reads QUDA's headers out of qudaDir, so both want an install prefix.
    add("qudaDir", _quda_dir(args, layout))
    add("cudaLibDir", _cuda_lib_dir(args))
    add("cudaMathLibDir", args.cudamathlibdir)
    add("nvhpcDir", args.nvhpcdir)
    add("primmeDir", args.primmedir)
    add("chromaDir", args.chromadir)
    add("gridDir", _grid_dir(args, layout))

    # ── Build behaviour ─────────────────────────────────────────────
    add("nimcache", args.nimcache)
    add("buildVerbosity", args.verbosity)

    # ── Environment variables baked into every QEX compile ──────────
    for e in envs + (args.env or []):
        settings.append(f"env:{e}")

    # ── Nim arguments baked into every QEX compile ──────────────────
    # 'nimargs' is substituted into qexconfig.nims as a Nim expression, so it
    # has to arrive as a Nim sequence literal rather than a bare string.
    nimargs = nimargs + (args.nim_arg or [])
    if nimargs:
        literal = ", ".join(f'"{a}"' for a in nimargs)
        settings.append(f"nimargs:@[{literal}]")

    # ── Extra raw settings passed through verbatim ──────────────────
    if args.extra_configure_settings:
        settings.extend(shlex.split(args.extra_configure_settings))

    return settings


def configure_qex(args: argparse.Namespace, layout: Layout, qex_src: Path, nim: Path) -> Path:
    """Run QEX's own configure in a dedicated build directory.

    QEX supports out-of-source builds, and this uses one: the checkout under
    ``src`` stays pristine while ``<prefix>/qex`` collects the generated
    ``Makefile``, ``qexconfig.nims``, and the ``qex`` / ``qex.nimble``
    symlinks that QEX's build tasks expect.
    """
    build_dir = ensure_dir(layout.prefix)
    settings = _configure_settings(args, layout, qex_src)
    run([str(qex_src / "configure")] + settings,
        cwd=build_dir, env={"NIM": str(nim)})

    config = build_dir / "qexconfig.nims"
    if not config.exists():
        raise RuntimeError(
            f"QEX configure completed but {config} was not created.\n"
            f"Quark's configure reads QEX's build settings from this file."
        )
    return build_dir


def install_nimble_dependencies(layout: Layout, nim: Path) -> None:
    """Install the Nim packages QEX declares in ``qex.nimble``.

    Run from the QEX build directory, where configure placed the
    ``qex.nimble`` symlink. A failure here is reported loudly but does not
    abort the run: the C libraries and QEX checkout are already in place, and
    this step is the one most likely to fail for reasons outside the build
    (network, a package registry hiccup, a transient upstream break).
    """
    nimble = nim.parent / "nimble"
    if not nimble.exists():
        warn(f"No nimble found next to {nim}; skipping QEX's Nim dependencies.\n"
             f"Install them by hand with 'nimble install -dy' in {layout.prefix}.")
        return
    try:
        run([str(nimble), "install", "-dy"], cwd=layout.prefix)
    except subprocess.CalledProcessError as exc:
        warn(f"Installing QEX's Nim dependencies failed: {exc}\n"
             f"QEX itself is configured and its C libraries are built.\n"
             f"Retry with 'nimble install -dy' in {layout.prefix},\n"
             f"or re-run with --skip-nimble to suppress this step.")


# ──────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────

EPILOG = """\
examples:
  # Default build: QMP over MPI, mpicc/mpicxx, no explicit SIMD intrinsics
  ./bootstrap --backend qex

  # Single-node build with no MPI
  ./bootstrap --backend qex --comms single --cc gcc --cpp g++

  # AVX2 with native optimisation
  ./bootstrap --backend qex --simd SSE,AVX --vlen 8 \\
      --cflags-speed "-Ofast -march=native -ffast-math"

  # AVX512 with clang under OpenMPI wrappers
  ./bootstrap --backend qex --cctype clang --cc mpicc --cpp mpicxx \\
      --env OMPI_CC=clang --env OMPI_CXX=clang++ \\
      --simd SSE,AVX,AVX512 --vlen 16

  # Build against an existing QMP/QIO installation
  ./bootstrap --backend qex --skip-deps \\
      --qmpdir /usr/local/qmp --qiodir /usr/local/qio

  # NVIDIA GPU build, compiled through QEX's nvcc wrapper
  ./bootstrap --backend qex --accelerator cuda --cuda-arch sm_90

  # AMD GPU build
  ./bootstrap --backend qex --accelerator hip

  # Intel GPU build
  ./bootstrap --backend qex --accelerator sycl

  # QEX solving through the Grid this prefix already bootstrapped
  ./bootstrap --backend grid --simd GPU --accelerator cuda \\
              --backend qex --with-grid

  # QEX built against QUDA
  ./bootstrap --backend quda --gpu-arch 80 --backend qex --with-quda

  # Explicit QUDA and CUDA locations
  ./bootstrap --backend qex --qudadir /path/to/quda \\
              --cudalibdir /usr/local/cuda/lib64

  # Pass extra settings straight to QEX's configure
  ./bootstrap --backend qex --extra-configure-settings="chromaDir:/path/to/chroma"
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="bootstrap qex",
        description="Bootstrap QEX and all of its dependencies for Quark.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=EPILOG,
    )

    add_common_arguments(p)

    # ── Per-dependency skips ────────────────────────────────────────
    dep = p.add_argument_group("per-dependency control")
    dep.add_argument("--skip-qmp", action="store_true", help="Skip building QMP")
    dep.add_argument("--skip-qio", action="store_true", help="Skip building QIO")
    dep.add_argument("--skip-nimble", action="store_true",
                     help="Skip installing the Nim packages QEX declares in qex.nimble")

    # ── Dependency prefix overrides (use pre-installed) ─────────────
    paths = p.add_argument_group("dependency prefix overrides (skip build, use existing)")
    paths.add_argument("--qmpdir", metavar="PREFIX",
                       help="Use QMP from this prefix instead of building it")
    paths.add_argument("--qiodir", metavar="PREFIX",
                       help="Use QIO from this prefix instead of building it")

    # ── Communications ──────────────────────────────────────────────
    comm = p.add_argument_group("communications")
    comm.add_argument("--comms", default="mpi", choices=["mpi", "single"],
                      help="QMP communications type (default: mpi)")

    # ── SIMD ────────────────────────────────────────────────────────
    simd = p.add_argument_group("SIMD target")
    simd.add_argument("--simd", default=None, metavar="LIST",
                      help="Comma separated SIMD intrinsics, e.g. 'SSE,AVX' or "
                           "'SSE,AVX,AVX512'. Pass '' for no explicit intrinsics "
                           "(QEX default).")
    simd.add_argument("--vlen", default=None, type=int, metavar="N",
                      help="Inner (SIMD) vector length, independent of hardware "
                           "SIMD width (QEX default: 8)")

    # ── Compilers and flags ─────────────────────────────────────────
    comp = p.add_argument_group("compiler overrides")
    comp.add_argument("--cctype", metavar="FAMILY",
                      help="Compiler family Nim generates flags for, typically "
                           "'gcc' or 'clang' (QEX default: gcc)")
    comp.add_argument("--lang", choices=["cc", "cpp"], metavar="cc|cpp",
                      help="Default language backend; 'cpp' is required for "
                           "Chroma and Grid (QEX default: cc)")
    comp.add_argument("--cc", metavar="COMPILER",
                      help="C compiler (QEX default: mpicc)")
    comp.add_argument("--cflags-always", metavar="FLAGS",
                      help="C flags for both debug and release builds")
    comp.add_argument("--cflags-debug", metavar="FLAGS", help="C flags for debug builds")
    comp.add_argument("--cflags-speed", metavar="FLAGS", help="C flags for release builds")
    comp.add_argument("--ld", metavar="LINKER", help="C linker (QEX default: same as --cc)")
    comp.add_argument("--ldflags", metavar="FLAGS", help="C linker flags")
    comp.add_argument("--cpp", metavar="COMPILER",
                      help="C++ compiler (QEX default: mpicxx)")
    comp.add_argument("--cppflags-always", metavar="FLAGS",
                      help="C++ flags for both debug and release builds")
    comp.add_argument("--cppflags-debug", metavar="FLAGS", help="C++ flags for debug builds")
    comp.add_argument("--cppflags-speed", metavar="FLAGS", help="C++ flags for release builds")
    comp.add_argument("--ldpp", metavar="LINKER", help="C++ linker (QEX default: same as --cpp)")
    comp.add_argument("--ldppflags", metavar="FLAGS", help="C++ linker flags")

    # ── Accelerator / GPU ───────────────────────────────────────────
    gpu = p.add_argument_group("accelerator / GPU")
    gpu.add_argument("--accelerator", default="none",
                     choices=["none", "cpu", "cuda", "hip", "sycl", "openmp"],
                     help="QEX accelerator backend, compiled in as "
                          "'-d:Backend=...' (default: none, meaning CPU)")
    gpu.add_argument("--cuda-arch", default="sm_80", metavar="ARCH",
                     help="CUDA GPU architecture passed to nvcc as -arch "
                          "(default: sm_80)")
    gpu.add_argument("--cuda-dir", default="/usr/local/cuda", metavar="PREFIX",
                     help="CUDA toolkit prefix (default: /usr/local/cuda)")
    gpu.add_argument("--nvcc", metavar="PATH",
                     help="nvcc executable (default: <cuda-dir>/bin/nvcc)")
    gpu.add_argument("--cuda-host-compiler", default="g++", metavar="COMPILER",
                     help="Host compiler nvcc drives, passed as -ccbin "
                          "(default: g++)")

    # ── Backend integrations ────────────────────────────────────────
    integ = p.add_argument_group("backend integrations")
    integ.add_argument("--with-grid", nargs="?", const="", default=None,
                       metavar="PREFIX",
                       help="Build QEX against Grid, so QEX itself can solve "
                            "through Grid. With no value, uses the Grid this "
                            "prefix already bootstrapped. Implies a C++ build.")
    integ.add_argument("--with-quda", nargs="?", const="", default=None,
                       metavar="PREFIX",
                       help="Build QEX against QUDA. With no value, uses the "
                            "QUDA this prefix already bootstrapped. Implies a "
                            "C++ build.")

    # ── Optional libraries ──────────────────────────────────────────
    opt = p.add_argument_group("optional libraries")
    opt.add_argument("--qudadir", metavar="PREFIX",
                     help="QUDA install prefix, overriding --with-quda")
    opt.add_argument("--cudalibdir", metavar="DIR", help="CUDA library directory")
    opt.add_argument("--cudamathlibdir", metavar="DIR", help="CUDA math library directory")
    opt.add_argument("--nvhpcdir", metavar="PREFIX", help="NVIDIA HPC SDK prefix")
    opt.add_argument("--primmedir", metavar="PREFIX", help="PRIMME eigensolver prefix")
    opt.add_argument("--chromadir", metavar="PREFIX", help="Chroma install prefix")
    opt.add_argument("--griddir", metavar="PREFIX",
                     help="Grid install prefix, overriding --with-grid")

    # ── Build behaviour ─────────────────────────────────────────────
    beh = p.add_argument_group("build behaviour")
    beh.add_argument("--nimcache", metavar="DIR",
                     help="Directory for generated C/C++ sources and objects "
                          "(QEX default: <build dir>/nimcache)")
    beh.add_argument("--verbosity", type=int, choices=[0, 1, 2, 3], metavar="N",
                     help="Nim build verbosity, 0-3 (QEX default: 1)")
    beh.add_argument("--env", action="append", metavar="NAME=VALUE",
                     help="Environment variable to define during every QEX build. "
                          "Repeatable, e.g. --env OMPI_CC=clang --env OMPI_CXX=clang++")
    beh.add_argument("--nim-arg", action="append", metavar="FLAG",
                     help="Extra Nim flag for every QEX build. Repeatable, "
                          "e.g. --nim-arg --listCmd --nim-arg -d:nc=4")

    # ── Source control ──────────────────────────────────────────────
    srcgrp = p.add_argument_group("source control")
    srcgrp.add_argument("--qex-repo", default="https://github.com/jcosborn/qex.git",
                        metavar="URL",
                        help="QEX git repository to clone "
                             "(default: https://github.com/jcosborn/qex.git)")
    srcgrp.add_argument("--qex-branch", default="devel", metavar="BRANCH",
                        help="QEX git branch to clone (default: devel)")
    srcgrp.add_argument("--qex-pull", action="store_true",
                        help="Run git pull in an existing QEX checkout")

    # ── Escape hatch ────────────────────────────────────────────────
    p.add_argument("--extra-configure-settings", metavar="'SETTINGS'",
                   help="Raw 'key:value' settings appended verbatim to QEX's configure")

    return p


# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────

# Each entry is (stage key, human label, skip flag, prefix-override flag).
DEPENDENCIES = [
    ("qmp", "Installing QMP", "skip_qmp", "qmpdir"),
    ("qio", "Installing QIO", "skip_qio", "qiodir"),
]


def _wanted(args: argparse.Namespace, skip_flag: str, with_flag: str) -> bool:
    return not getattr(args, skip_flag) and not getattr(args, with_flag)


def _stage_list(args: argparse.Namespace) -> list[tuple[str, str]]:
    stages: list[tuple[str, str]] = []
    if not args.skip_deps:
        for key, label, skip_flag, with_flag in DEPENDENCIES:
            if _wanted(args, skip_flag, with_flag):
                stages.append((key, label))
    if not args.skip_nim:
        stages.append(("nim", "Installing Nim"))
    stages.append(("qex", "Configuring QEX"))
    if not args.skip_nimble:
        stages.append(("nimble", "Installing QEX's Nim dependencies"))
    return stages


def _usqcd_cc(args: argparse.Namespace) -> str:
    """Return the C compiler QMP and QIO are built with.

    QEX's own default is ``mpicc``, and QMP and QIO must be built with the
    same compiler QEX links them against, so the choice follows ``--cc``.
    Without MPI there is no wrapper to use, so fall back to a plain compiler.
    """
    if args.cc: return args.cc
    return "mpicc" if args.comms == "mpi" else "gcc"


def bootstrap(args: argparse.Namespace, layout: Layout, cc: str, cxx: str) -> None:
    """Install QEX and its dependencies into *layout*.

    The compiler is resolved by the caller so that bootstrapping several
    backends in one invocation resolves it exactly once.
    """
    stages = StageTracker(BACKEND, _stage_list(args))
    usqcd_cc = _usqcd_cc(args)

    if not args.skip_deps:
        if args.use_spack:
            ensure_spack(layout)

        if _wanted(args, "skip_qmp", "qmpdir"):
            stages.begin("qmp")
            build_or_spack("qmp", build_qmp, (layout, usqcd_cc, args.comms, args.jobs),
                           layout, use_spack=args.use_spack, jobs=args.jobs)

        if _wanted(args, "skip_qio", "qiodir"):
            stages.begin("qio")
            qmp_prefix = Path(args.qmpdir) if args.qmpdir else layout.deps
            build_or_spack("qio", build_qio, (layout, usqcd_cc, qmp_prefix, args.jobs),
                           layout, use_spack=args.use_spack, jobs=args.jobs)
    else:
        print("--skip-deps: skipping all dependency builds")

    if not args.skip_nim:
        stages.begin("nim")
    nim = resolve_nim(layout, skip=args.skip_nim, version=args.nim_version)

    stages.begin("qex")
    qex_src = clone_qex(args, layout)
    build_dir = configure_qex(args, layout, qex_src, nim)

    if not args.skip_nimble:
        stages.begin("nimble")
        install_nimble_dependencies(layout, nim)

    write_manifest(layout, BACKEND, {
        "prefix": str(build_dir),
        "config": str(build_dir / "qexconfig.nims"),
        "source": str(qex_src),
        "repo": args.qex_repo,
        "branch": args.qex_branch,
        "deps": str(layout.deps),
        "qmpdir": str(args.qmpdir or layout.deps),
        "qiodir": str(args.qiodir or layout.deps),
        "cc": args.cc or usqcd_cc,
        "cxx": args.cpp or cxx,
        "comms": args.comms,
        "simd": args.simd if args.simd is not None else "",
        "language": _language(args) or "cc",
        "accelerator": QEX_BACKENDS[args.accelerator],
        "griddir": _grid_dir(args, layout),
        "qudadir": _quda_dir(args, layout),
        "nim": str(nim),
    }, nim=nim)

    stages.finish()
    print(f"\n{'=' * 66}")
    print(f"QEX configured in: {build_dir}")
    print(f"Build settings:    {build_dir / 'qexconfig.nims'}")
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
