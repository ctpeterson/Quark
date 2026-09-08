"""
grid.py — download, build, and install Grid and its dependencies.

build: build/grid.py
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

Usage
-----
    python3 build/grid.py [OPTIONS]

Normally invoked through the top-level ``bootstrap`` driver:

    ./bootstrap grid [OPTIONS]

Run with ``--help`` for the full list of flags. Everything lands under the
prefix described in ``common.py``:

    <prefix>/deps/grid      GMP, MPFR, FFTW, OpenSSL, HDF5, c-lime, libunwind
    <prefix>/nim            Nim toolchain
    <prefix>/grid           Grid install prefix, including bin/grid-config
    <prefix>/src            source and out-of-source build trees

``bin/grid-config`` in the Grid prefix is the record of how Grid was built:
every MPI, OpenMP, SIMD, and accelerator flag is baked into it, and Quark's
`configure` reads it back rather than re-deriving any of it.

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
    Layout, StageTracker, add_common_arguments, build_or_spack, download,
    ensure_compiler, ensure_dir, ensure_spack, lib_installed, resolve_nim,
    run, warn, write_manifest,
)

BACKEND = "grid"


# ──────────────────────────────────────────────────────────────────────
# Dependency builders
# ──────────────────────────────────────────────────────────────────────

def build_gmp(layout: Layout, jobs: str) -> None:
    if lib_installed(layout.deps, "libgmp"):
        print("GMP already installed, skipping.")
        return
    src = layout.source("gmp")
    tarball = "gmp-6.3.0.tar.xz"
    url = f"https://gmplib.org/download/gmp/{tarball}"
    if not (src / tarball).exists(): download(url, src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / "gmp-6.3.0"
    run(f"./configure --prefix={layout.deps} --enable-cxx", cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)


def build_mpfr(layout: Layout, gmp_prefix: Path, jobs: str) -> None:
    if lib_installed(layout.deps, "libmpfr"):
        print("MPFR already installed, skipping.")
        return
    src = layout.source("mpfr")
    tarball = "mpfr-4.2.1.tar.xz"
    url = f"https://ftp.gnu.org/gnu/mpfr/{tarball}"
    if not (src / tarball).exists(): download(url, src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / "mpfr-4.2.1"
    run(f"./configure --prefix={layout.deps} --with-gmp={gmp_prefix}", cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)


def build_fftw(layout: Layout, jobs: str) -> None:
    if lib_installed(layout.deps, "libfftw3"):
        print("FFTW already installed, skipping.")
        return
    src = layout.source("fftw")
    tarball = "fftw-3.3.10.tar.gz"
    url = f"https://www.fftw.org/{tarball}"
    if not (src / tarball).exists(): download(url, src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / "fftw-3.3.10"

    # Double precision
    run(f"./configure --prefix={layout.deps}", cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)
    run("make clean", cwd=build_dir)

    # Single precision (Grid needs both)
    run(f"./configure --prefix={layout.deps} --enable-float", cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)


def build_openssl(layout: Layout, jobs: str) -> None:
    if lib_installed(layout.deps, "libssl"):
        print("OpenSSL already installed, skipping.")
        return
    src = layout.source("openssl")
    tarball = "openssl-3.2.1.tar.gz"
    url = f"https://github.com/openssl/openssl/releases/download/openssl-3.2.1/{tarball}"
    if not (src / tarball).exists(): download(url, src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / "openssl-3.2.1"
    run(f"./config --prefix={layout.deps} --openssldir={layout.deps / 'ssl'}", cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install_sw", cwd=build_dir)


def build_hdf5(layout: Layout, jobs: str) -> None:
    if lib_installed(layout.deps, "libhdf5"):
        print("HDF5 already installed, skipping.")
        return
    src = layout.source("hdf5")
    tag = "hdf5_1.14.6"
    tarball = f"{tag}.tar.gz"
    url = f"https://github.com/HDFGroup/hdf5/archive/refs/tags/{tarball}"
    if not (src / tarball).exists(): download(url, src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / f"hdf5-{tag}"
    run(f"./configure --prefix={layout.deps} --enable-cxx "
        f"--enable-build-mode=production", cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)


def build_lime(layout: Layout, jobs: str) -> None:
    if lib_installed(layout.deps, "liblime"):
        print("LIME (c-lime) already installed, skipping.")
        return
    src = layout.source("lime")
    clone_dir = src / "c-lime"
    if not clone_dir.exists():
        run("git clone https://github.com/usqcd-software/c-lime.git", cwd=src)
    run("./autogen.sh", cwd=clone_dir)
    run(f"./configure --prefix={layout.deps}", cwd=clone_dir)
    run(f"make -j{jobs}", cwd=clone_dir)
    run("make install", cwd=clone_dir)


def build_libunwind(layout: Layout, jobs: str) -> None:
    if lib_installed(layout.deps, "libunwind"):
        print("libunwind already installed, skipping.")
        return
    src = layout.source("libunwind")
    tarball = "libunwind-1.8.1.tar.gz"
    url = f"https://github.com/libunwind/libunwind/releases/download/v1.8.1/{tarball}"
    if not (src / tarball).exists(): download(url, src / tarball)
    run(f"tar xf {tarball}", cwd=src)
    build_dir = src / "libunwind-1.8.1"
    run(f"./configure --prefix={layout.deps}", cwd=build_dir)
    run(f"make -j{jobs}", cwd=build_dir)
    run("make install", cwd=build_dir)


# ──────────────────────────────────────────────────────────────────────
# Grid builder
# ──────────────────────────────────────────────────────────────────────

def _patch_setdevice(grid_src: Path) -> None:
    """Repair Grid's ``--enable-setdevice`` AC_ARG_ENABLE clause.

    Some Grid revisions declare the option with a shell variable that does not
    match the one the rest of ``configure.ac`` reads, so ``--enable-setdevice``
    is silently ignored. Rewrite the clause in place, and do nothing when the
    revision is already correct or has already been patched.
    """
    config_path = grid_src / "configure.ac"
    marker = "ac_SETDEVICE=${enable_SETDEVICE}]"
    original = config_path.read_text()
    if marker not in original:
        print("configure.ac needs no setdevice patch, skipping.")
        return

    replacement = (
        "AC_ARG_ENABLE([setdevice],[AS_HELP_STRING([--enable-setdevice | "
        "--disable-setdevice],[Set GPU to rank in node with cudaSetDevice "
        "or similar])],[ac_setdevice=${enable_setdevice}],[ac_setdevice=no])"
    )
    patched = "\n".join(
        replacement if marker in line else line
        for line in original.splitlines()
    ) + "\n"

    # Write through a temporary file so an interrupted run cannot leave a
    # half-written configure.ac behind.
    tmp_path = grid_src / "configure.ac.quark-tmp"
    tmp_path.write_text(patched)
    tmp_path.replace(config_path)
    print("Applied setdevice patch to configure.ac")


def _configure_flags(args: argparse.Namespace, layout: Layout, grid_install: Path) -> list[str]:
    """Assemble Grid's configure arguments from the parsed options."""
    cmd: list[str] = [f"--prefix={grid_install}"]

    # ── SIMD ────────────────────────────────────────────────────────
    cmd.append(f"--enable-simd={args.simd}")
    if args.gen_simd_width is not None:
        cmd.append(f"--enable-gen-simd-width={args.gen_simd_width}")
    if args.gen_scalar:
        cmd.append("--enable-gen-scalar=yes")

    # ── Communications ──────────────────────────────────────────────
    cmd.append(f"--enable-comms={args.comms}")

    # ── Accelerator (GPU) ───────────────────────────────────────────
    cmd.append(f"--enable-accelerator={args.accelerator}")
    if args.unified is not None:
        cmd.append(f"--enable-unified={'yes' if args.unified else 'no'}")
    if args.accelerator_aware_mpi is not None:
        cmd.append("--enable-accelerator-aware-mpi="
                   f"{'yes' if args.accelerator_aware_mpi else 'no'}")
    if args.setdevice:
        cmd.append("--enable-setdevice")

    # ── Shared memory ───────────────────────────────────────────────
    if args.shm is not None: cmd.append(f"--enable-shm={args.shm}")
    if args.shmpath is not None: cmd.append(f"--enable-shmpath={args.shmpath}")
    if args.shm_force_mpi: cmd.append("--enable-shm-force-mpi")
    if args.shm_fast_path: cmd.append("--enable-shm-fast-path")

    # ── Allocator ───────────────────────────────────────────────────
    if args.alloc_align is not None:
        cmd.append(f"--enable-alloc-align={args.alloc_align}")
    if args.alloc_cache is not None:
        cmd.append(f"--enable-alloc-cache={'yes' if args.alloc_cache else 'no'}")

    # ── Gauge group / fermions ──────────────────────────────────────
    cmd.append(f"--enable-Nc={args.nc}")
    if args.sp: cmd.append("--enable-Sp=yes")
    if args.fermion_reps is not None:
        cmd.append(f"--enable-fermion-reps={'yes' if args.fermion_reps else 'no'}")
    if args.gparity is not None:
        cmd.append(f"--enable-gparity={'yes' if args.gparity else 'no'}")
    if args.zmobius is not None:
        cmd.append(f"--enable-zmobius={'yes' if args.zmobius else 'no'}")

    # ── RNG ─────────────────────────────────────────────────────────
    cmd.append(f"--enable-rng={args.rng}")

    # ── Debug / optimisation ────────────────────────────────────────
    if args.debug: cmd.append("--enable-debug=yes")

    # ── Timers ──────────────────────────────────────────────────────
    if args.no_timers: cmd.append("--enable-timers=no")

    # ── FP16 ────────────────────────────────────────────────────────
    if args.sfw_fp16 is not None:
        cmd.append(f"--enable-sfw-fp16={'yes' if args.sfw_fp16 else 'no'}")

    # ── Tracing ─────────────────────────────────────────────────────
    if args.tracing is not None: cmd.append(f"--enable-tracing={args.tracing}")

    # ── Reduction ───────────────────────────────────────────────────
    if args.reduction is not None: cmd.append(f"--enable-reduction={args.reduction}")

    # ── Checksums / logging ─────────────────────────────────────────
    if args.checksum_comms: cmd.append("--enable-checksum-comms=yes")
    if args.log_views: cmd.append("--enable-log-views=yes")

    # ── Chroma regression ───────────────────────────────────────────
    if args.chroma: cmd.append("--enable-chroma")

    # ── Dependency paths ────────────────────────────────────────────
    # Point at Grid's own deps prefix unless the user named another one.
    cmd.append(f"--with-gmp={args.with_gmp or layout.deps}")
    cmd.append(f"--with-mpfr={args.with_mpfr or layout.deps}")

    if args.with_fftw or lib_installed(layout.deps, "libfftw3"):
        cmd.append(f"--with-fftw={args.with_fftw or layout.deps}")
    if args.with_hdf5 or lib_installed(layout.deps, "libhdf5"):
        cmd.append(f"--with-hdf5={args.with_hdf5 or layout.deps}")
    if args.with_lime or lib_installed(layout.deps, "liblime"):
        cmd.append(f"--with-lime={args.with_lime or layout.deps}")
    if args.with_openssl or lib_installed(layout.deps, "libssl"):
        cmd.append(f"--with-openssl={args.with_openssl or layout.deps}")
    if args.with_unwind or lib_installed(layout.deps, "libunwind"):
        cmd.append(f"--with-unwind={args.with_unwind or layout.deps}")

    # ── LAPACK / MKL / IPP ──────────────────────────────────────────
    if args.lapack is not None: cmd.append(f"--enable-lapack={args.lapack}")
    if args.mkl is not None: cmd.append(f"--enable-mkl={args.mkl}")
    if args.ipp is not None: cmd.append(f"--enable-ipp={args.ipp}")

    # ── Compiler overrides ──────────────────────────────────────────
    if args.cxx: cmd.append(f"CXX={args.cxx}")
    if args.cc: cmd.append(f"CC={args.cc}")
    if args.mpicxx: cmd.append(f"MPICXX={args.mpicxx}")
    if args.cxxflags: cmd.append(f"CXXFLAGS={args.cxxflags}")
    if args.ldflags: cmd.append(f"LDFLAGS={args.ldflags}")

    # ── Extra raw flags passed through verbatim ─────────────────────
    if args.extra_configure_flags:
        cmd.extend(shlex.split(args.extra_configure_flags))

    return cmd


def build_grid(args: argparse.Namespace, layout: Layout) -> Path:
    """Clone, configure, build, and install Grid. Returns the install prefix."""
    grid_src = layout.src / "grid"
    grid_build = layout.src / "grid-build"
    grid_install = layout.prefix

    if not grid_src.exists():
        run(f"git clone --branch {args.grid_branch} {args.grid_repo} {grid_src}")
    elif args.grid_pull:
        run("git pull", cwd=grid_src)

    _patch_setdevice(grid_src)
    run("./bootstrap.sh", cwd=grid_src)

    ensure_dir(grid_build)
    configure_cmd = [str(grid_src / "configure")] + _configure_flags(args, layout, grid_install)
    run(configure_cmd, cwd=grid_build)

    run(f"make -j{args.jobs}", cwd=grid_build)
    if args.run_tests:
        run(f"make -j{args.jobs} tests", cwd=grid_build)
        run("make check", cwd=grid_build)
    run("make install", cwd=grid_build)

    return grid_install


# ──────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────

EPILOG = """\
examples:
  # Minimal CPU-only build (GEN SIMD, no MPI)
  ./bootstrap grid --comms none

  # AVX2 + MPI auto-detection
  ./bootstrap grid --simd AVX2 --comms mpi-auto

  # CUDA GPU build
  ./bootstrap grid --simd GPU --comms mpi-auto --accelerator cuda --cxx nvcc

  # AMD GPU (HIP) build
  ./bootstrap grid --simd GPU --comms mpi-auto --accelerator hip --cxx hipcc

  # Intel GPU (SYCL) build
  ./bootstrap grid --simd GPU --comms mpi-auto --accelerator sycl --cxx dpcpp

  # Knights Landing
  ./bootstrap grid --simd KNL --comms mpi3-auto --mkl yes --cxx icpc --mpicxx mpiicpc

  # A64FX (Fugaku / ARM SVE)
  ./bootstrap grid --simd A64FX --comms mpi-auto

  # Skip dependencies (already installed system-wide)
  ./bootstrap grid --skip-deps --with-gmp /usr --with-mpfr /usr

  # Install all dependencies via Spack instead of building from source
  ./bootstrap grid --use-spack

  # Use the system default compiler (GCC) instead of LLVM/Clang
  ./bootstrap grid --no-llvm

  # Pass extra flags directly to Grid's configure
  ./bootstrap grid --extra-configure-flags="--disable-fermion-reps --enable-Nc=4"
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="bootstrap grid",
        description="Bootstrap Grid and all of its dependencies for Quark.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=EPILOG,
    )

    add_common_arguments(p)

    # ── Per-dependency skips ────────────────────────────────────────
    dep = p.add_argument_group("per-dependency control")
    dep.add_argument("--skip-gmp", action="store_true", help="Skip building GMP")
    dep.add_argument("--skip-mpfr", action="store_true", help="Skip building MPFR")
    dep.add_argument("--skip-fftw", action="store_true", help="Skip building FFTW")
    dep.add_argument("--skip-openssl", action="store_true", help="Skip building OpenSSL")
    dep.add_argument("--skip-hdf5", action="store_true", help="Skip building HDF5")
    dep.add_argument("--skip-lime", action="store_true", help="Skip building c-lime")
    dep.add_argument("--skip-libunwind", action="store_true", help="Skip building libunwind")

    # ── Dependency prefix overrides (use pre-installed) ─────────────
    paths = p.add_argument_group("dependency prefix overrides (skip build, use existing)")
    paths.add_argument("--with-gmp", metavar="PREFIX",
                       help="Use GMP from this prefix instead of building it")
    paths.add_argument("--with-mpfr", metavar="PREFIX",
                       help="Use MPFR from this prefix instead of building it")
    paths.add_argument("--with-fftw", metavar="PREFIX",
                       help="Use FFTW from this prefix instead of building it")
    paths.add_argument("--with-openssl", metavar="PREFIX",
                       help="Use OpenSSL from this prefix instead of building it")
    paths.add_argument("--with-hdf5", metavar="PREFIX",
                       help="Use HDF5 from this prefix instead of building it")
    paths.add_argument("--with-lime", metavar="PREFIX",
                       help="Use LIME (c-lime) from this prefix instead of building it")
    paths.add_argument("--with-unwind", metavar="PREFIX",
                       help="Use libunwind from this prefix instead of building it")

    # ── SIMD ────────────────────────────────────────────────────────
    simd = p.add_argument_group("SIMD target")
    simd.add_argument("--simd", default="GEN",
                      choices=["GEN", "SSE4", "AVX", "AVXFMA", "AVXFMA4", "AVX2",
                               "AVX512", "SKL", "KNL", "KNC",
                               "NEONv8", "A64FX", "QPX", "BGQ",
                               "GPU", "GPU-RRII"],
                      help="SIMD instruction set (default: GEN)")
    simd.add_argument("--gen-simd-width", type=int, metavar="BYTES",
                      help="Width in bytes of generic SIMD vectors (default: 64)")
    simd.add_argument("--gen-scalar", action="store_true",
                      help="Use generic scalar (non-SIMD) implementation")

    # ── Communications ──────────────────────────────────────────────
    comm = p.add_argument_group("communications")
    comm.add_argument("--comms", default="mpi-auto",
                      choices=["none", "mpi", "mpi-auto", "mpi3", "mpi3-auto"],
                      help="Communication backend (default: mpi-auto)")

    # ── Accelerator (GPU) ───────────────────────────────────────────
    gpu = p.add_argument_group("accelerator / GPU")
    gpu.add_argument("--accelerator", default="none",
                     choices=["none", "cuda", "sycl", "hip"],
                     help="GPU acceleration backend (default: none)")
    gpu.add_argument("--unified", default=None, action=argparse.BooleanOptionalAction,
                     help="Unified virtual address space for accelerator loops (default: yes)")
    gpu.add_argument("--accelerator-aware-mpi", default=None,
                     action=argparse.BooleanOptionalAction,
                     help="Allow MPI transfers from device memory (default: yes)")
    gpu.add_argument("--setdevice", action="store_true",
                     help="Set GPU device to node-local rank via cudaSetDevice / hipSetDevice")

    # ── Shared memory ───────────────────────────────────────────────
    shm = p.add_argument_group("shared memory")
    shm.add_argument("--shm", default=None,
                     choices=["shmopen", "shmget", "hugetlbfs", "shmnone", "nvlink", "no", "none"],
                     help="SHM allocation technique")
    shm.add_argument("--shmpath", metavar="PATH",
                     help="Mmap base path for hugetlbfs (default: /var/lib/hugetlbfs/…)")
    shm.add_argument("--shm-force-mpi", action="store_true",
                     help="Force MPI within shared memory nodes")
    shm.add_argument("--shm-fast-path", action="store_true",
                     help="Allow kernels to remote-copy over intranode links")

    # ── Allocator ───────────────────────────────────────────────────
    alloc = p.add_argument_group("allocator")
    alloc.add_argument("--alloc-align", choices=["2MB", "4k"],
                       help="Alignment of Grid allocator (default: 2MB)")
    alloc.add_argument("--alloc-cache", default=None, action=argparse.BooleanOptionalAction,
                       help="Cache pool of recent frees for reuse (default: yes)")

    # ── Gauge group & fermion reps ──────────────────────────────────
    phys = p.add_argument_group("gauge group / fermion content")
    phys.add_argument("--nc", default="3", choices=["2", "3", "4", "5", "8"],
                      help="Number of colours Nc (default: 3)")
    phys.add_argument("--sp", action="store_true",
                      help="Use symplectic gauge group Sp(2N) instead of SU(N)")
    phys.add_argument("--fermion-reps", default=None, action=argparse.BooleanOptionalAction,
                      help="Enable extra fermion representations (default: yes)")
    phys.add_argument("--gparity", default=None, action=argparse.BooleanOptionalAction,
                      help="Enable G-parity boundary conditions (default: yes)")
    phys.add_argument("--zmobius", default=None, action=argparse.BooleanOptionalAction,
                      help="Enable Zmöbius fermion actions (default: yes)")

    # ── RNG ─────────────────────────────────────────────────────────
    rng = p.add_argument_group("random number generator")
    rng.add_argument("--rng", default="sitmo",
                     choices=["sitmo", "ranlux48", "mt19937"],
                     help="RNG implementation (default: sitmo)")

    # ── Intel libraries ─────────────────────────────────────────────
    intel = p.add_argument_group("Intel libraries")
    intel.add_argument("--mkl", metavar="yes|no|PREFIX",
                       help="Use Intel MKL for LAPACK and FFTW (default: no)")
    intel.add_argument("--ipp", metavar="yes|no|PREFIX",
                       help="Use Intel IPP for fast CRC32C (default: no)")

    # ── LAPACK ──────────────────────────────────────────────────────
    la = p.add_argument_group("LAPACK")
    la.add_argument("--lapack", metavar="yes|no|PREFIX",
                    help="Enable LAPACK for Lanczos eigensolver (default: no)")

    # ── FP16 ────────────────────────────────────────────────────────
    fp = p.add_argument_group("precision")
    fp.add_argument("--sfw-fp16", default=None, action=argparse.BooleanOptionalAction,
                    help="Software FP16 conversion for comms (default: yes)")

    # ── Tracing ─────────────────────────────────────────────────────
    trace = p.add_argument_group("tracing / profiling")
    trace.add_argument("--tracing", default=None,
                       choices=["none", "nvtx", "roctx", "timer"],
                       help="Profiling tracing backend (default: none)")

    # ── Reduction ───────────────────────────────────────────────────
    red = p.add_argument_group("reduction")
    red.add_argument("--reduction", default=None, choices=["mpi", "grid"],
                     help="Internal reduction implementation (default: grid)")

    # ── Diagnostics ─────────────────────────────────────────────────
    diag = p.add_argument_group("diagnostics")
    diag.add_argument("--checksum-comms", action="store_true",
                      help="Checksum all MPI communication")
    diag.add_argument("--log-views", action="store_true",
                      help="Log all view open/close events")
    diag.add_argument("--debug", action="store_true",
                      help="Build with -g instead of -O3")

    # ── Timers ──────────────────────────────────────────────────────
    tim = p.add_argument_group("timers")
    tim.add_argument("--no-timers", action="store_true",
                     help="Disable high-resolution timers")

    # ── Chroma ──────────────────────────────────────────────────────
    ch = p.add_argument_group("chroma")
    ch.add_argument("--chroma", action="store_true",
                    help="Build with Chroma regression test support")

    # ── Compiler overrides ──────────────────────────────────────────
    comp = p.add_argument_group("compiler overrides")
    comp.add_argument("--cxx", metavar="COMPILER",
                      help="C++ compiler (e.g. g++, icpc, nvcc, hipcc, dpcpp)")
    comp.add_argument("--cc", metavar="COMPILER", help="C compiler")
    comp.add_argument("--mpicxx", metavar="COMPILER",
                      help="MPI C++ wrapper (e.g. mpicxx, mpiicpc)")
    comp.add_argument("--cxxflags", metavar="FLAGS", help="Extra CXXFLAGS")
    comp.add_argument("--ldflags", metavar="FLAGS", help="Extra LDFLAGS")

    # ── Git / build control ─────────────────────────────────────────
    build = p.add_argument_group("source control")
    build.add_argument("--grid-repo",
                       default="https://github.com/ctpeterson/Grid-HISQ.git",
                       metavar="URL",
                       help="Grid git repository to clone (default: Grid-HISQ, the "
                            "fork Quark targets until it merges into Grid proper). "
                            "Pass https://github.com/paboyle/Grid.git for upstream.")
    build.add_argument("--grid-branch", default="develop", metavar="BRANCH",
                       help="Grid git branch to clone (default: develop)")
    build.add_argument("--grid-pull", action="store_true",
                       help="Run git pull in an existing Grid checkout")
    build.add_argument("--run-tests", action="store_true",
                       help="Build and run Grid's test suite after compilation")

    # ── Escape hatch ────────────────────────────────────────────────
    p.add_argument("--extra-configure-flags", metavar="'FLAGS'",
                   help="Raw string appended verbatim to the configure invocation")

    return p


# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────

# Each entry is (stage key, human label, skip flag, prefix-override flag, builder).
DEPENDENCIES = [
    ("gmp",       "Installing GMP",       "skip_gmp",       "with_gmp"),
    ("mpfr",      "Installing MPFR",      "skip_mpfr",      "with_mpfr"),
    ("fftw",      "Installing FFTW",      "skip_fftw",      "with_fftw"),
    ("openssl",   "Installing OpenSSL",   "skip_openssl",   "with_openssl"),
    ("hdf5",      "Installing HDF5",      "skip_hdf5",      "with_hdf5"),
    ("lime",      "Installing c-lime",    "skip_lime",      "with_lime"),
    ("libunwind", "Installing libunwind", "skip_libunwind", "with_unwind"),
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
    stages.append(("grid", "Building Grid"))
    return stages


def bootstrap(args: argparse.Namespace, layout: Layout, cc: str, cxx: str) -> None:
    """Install Grid and its dependencies into *layout*.

    The compiler is resolved by the caller so that bootstrapping several
    backends in one invocation resolves it exactly once.
    """
    stages = StageTracker(BACKEND, _stage_list(args))

    if not args.skip_deps:
        if args.use_spack:
            ensure_spack(layout)

        builders = {
            "gmp":       (build_gmp,       (layout, args.jobs)),
            "mpfr":      (build_mpfr,      (layout, Path(args.with_gmp) if args.with_gmp
                                            else layout.deps, args.jobs)),
            "fftw":      (build_fftw,      (layout, args.jobs)),
            "openssl":   (build_openssl,   (layout, args.jobs)),
            "hdf5":      (build_hdf5,      (layout, args.jobs)),
            "lime":      (build_lime,      (layout, args.jobs)),
            "libunwind": (build_libunwind, (layout, args.jobs)),
        }
        for key, _label, skip_flag, with_flag in DEPENDENCIES:
            if not _wanted(args, skip_flag, with_flag): continue
            stages.begin(key)
            fn, fn_args = builders[key]
            build_or_spack(key, fn, fn_args, layout,
                           use_spack=args.use_spack, jobs=args.jobs)
    else:
        print("--skip-deps: skipping all dependency builds")

    if not args.skip_nim:
        stages.begin("nim")
    nim = resolve_nim(layout, skip=args.skip_nim, version=args.nim_version)

    stages.begin("grid")
    grid_install = build_grid(args, layout)

    grid_config = grid_install / "bin" / "grid-config"
    if not grid_config.exists():
        warn(f"Grid installed but {grid_config} is missing.\n"
             f"Quark's configure reads Grid's build settings from grid-config;\n"
             f"without it you will have to pass those flags to configure by hand.")

    write_manifest(layout, BACKEND, {
        "prefix": str(grid_install),
        "config": str(grid_config) if grid_config.exists() else "",
        "source": str(layout.src / "grid"),
        "repo": args.grid_repo,
        "branch": args.grid_branch,
        "deps": str(layout.deps),
        "cc": args.cc or cc,
        "cxx": args.cxx or cxx,
        "simd": args.simd,
        "comms": args.comms,
        "accelerator": args.accelerator,
        "nim": str(nim),
    }, nim=nim)

    stages.finish()
    print(f"\n{'=' * 66}")
    print(f"Grid installed to: {grid_install}")
    print(f"Build settings:    {grid_config}")
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
