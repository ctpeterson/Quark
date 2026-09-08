"""
common.py — machinery shared by Quark's backend bootstrap scripts.

build: build/common.py
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

A backend bootstrap script owns the knowledge of how to obtain, configure, and
build one backend and its dependencies. Everything that is not backend-specific
lives here: the install layout, command execution, downloads, Spack fallback,
compiler resolution, the Nim toolchain, stage reporting, and the manifest that
records what a bootstrap run produced.

Install layout
--------------
Every bootstrap run writes into a single prefix (``local/`` by default):

    local/
        src/            source and download trees, shared across backends
        deps/<backend>  that backend's C/C++ dependency prefix: bin lib include
        nim/            Nim toolchain prefix (bin/nim, bin/nimble)
        grid/           Grid install prefix        (bin/grid-config)
        qex/            QEX build directory        (qexconfig.nims, Makefile)
        bootstrap.json  manifest of everything installed so far

The rule is uniform: each backend owns one dependency prefix and one install
directory, both named after the backend, and every source or download tree
lives under the shared ``src``.

Dependency prefixes are per-backend rather than shared because backends
disagree about the same library: QIO installs its own ``liblime`` and lime
headers, which would collide with the c-lime that Grid needs, and the two
backends may be built with different compilers and MPI wrappers. Isolating
them is what makes installing several backends side by side safe. Downloads
and toolchains under ``src`` stay shared, since those are identical.

The manifest accumulates rather than overwrites: bootstrapping a second
backend leaves the first one's entry intact, so `configure` sees every
backend available on the machine.

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
import json
import multiprocessing
import os
import platform
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

NJOBS = str(multiprocessing.cpu_count())

# Repository root, derived from this file's location rather than the working
# directory, so a bootstrap run is independent of where it was invoked.
QUARK_ROOT = Path(__file__).resolve().parent.parent


# ──────────────────────────────────────────────────────────────────────
# Command execution and downloads
# ──────────────────────────────────────────────────────────────────────

def run(cmd: str | list[str], *, cwd: Path | None = None, env: dict | None = None) -> None:
    """Run a shell command, streaming output, aborting on failure."""
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)
    merged_env = {**os.environ, **(env or {})}
    print(f"\n>>> {' '.join(cmd)}")
    subprocess.check_call(cmd, cwd=cwd, env=merged_env)


def capture(cmd: str | list[str], *, cwd: Path | None = None) -> str:
    """Run a command and return its stripped stdout."""
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)
    return subprocess.check_output(cmd, cwd=cwd, env=os.environ, text=True).strip()


def ensure_dir(p: Path) -> Path:
    p.mkdir(parents=True, exist_ok=True)
    return p


def which(name: str) -> str | None:
    return shutil.which(name)


def download(url: str, dest: Path) -> None:
    """Download a URL to dest, verifying we didn't get an HTML error page."""
    run(["curl", "-fL", "-o", str(dest), url])
    # Sanity-check: if the server gave us HTML instead of a tarball, abort early
    # rather than letting tar fail with a confusing message.
    with open(dest, "rb") as f:
        header = f.read(256)
    if b"<html" in header.lower() or b"<!doctype" in header.lower():
        dest.unlink()
        raise RuntimeError(
            f"Download of {url} returned an HTML page, not an archive.\n"
            f"The URL may have changed. Please check it manually."
        )


def host_arch() -> str:
    """Return the host machine as one of 'x64' or 'arm64'."""
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"): return "x64"
    if machine in ("aarch64", "arm64"): return "arm64"
    raise RuntimeError(f"Unsupported architecture: {machine}")


# ──────────────────────────────────────────────────────────────────────
# Install layout
# ──────────────────────────────────────────────────────────────────────

class Layout:
    """The directory layout one backend bootstrap writes into.

    ``root`` is the prefix every artifact lands under. ``src`` holds source
    and download trees and is shared across backends; ``deps`` and ``prefix``
    belong to this backend alone.
    """

    def __init__(self, root: Path, backend: str) -> None:
        self.root = root.resolve()
        self.backend = backend
        self.src = self.root / "src"
        self.deps = self.root / "deps" / backend
        self.prefix = self.root / backend
        self.nim = self.root / "nim"
        self.manifest = self.root / "bootstrap.json"

    def create(self) -> None:
        ensure_dir(self.root)
        ensure_dir(self.src)
        ensure_dir(self.deps)

    def source(self, name: str) -> Path:
        """Return (and create) the source/download tree directory for *name*."""
        return ensure_dir(self.src / name)


# ──────────────────────────────────────────────────────────────────────
# Terminal title and stage progress
# ──────────────────────────────────────────────────────────────────────

def _set_terminal_title(title: str) -> None:
    """Set the terminal window/tab title via an OSC escape sequence."""
    # Works in xterm, iTerm2, GNOME Terminal, Windows Terminal, etc.
    sys.stdout.write(f"\033]0;{title}\007")
    sys.stdout.flush()


class StageTracker:
    """Track and display bootstrap progress.

    Usage::

        stages = StageTracker("grid", [
            ("compiler", "Resolving compiler"),
            ("gmp",      "Installing GMP"),
        ])
        stages.begin("compiler")
        # … do work …
        stages.begin("gmp")
        stages.finish()
    """

    def __init__(self, label: str, steps: list[tuple[str, str]]) -> None:
        self._label = label
        self._steps = steps
        self._total = len(steps)
        self._index: dict[str, int] = {key: i for i, (key, _) in enumerate(steps)}

    def begin(self, key: str) -> None:
        """Mark stage *key* as active."""
        idx = self._index[key]
        num = idx + 1
        label = self._steps[idx][1]
        banner = f"[{num}/{self._total}] {label}"
        _set_terminal_title(f"Quark {self._label} bootstrap {banner}")
        print(f"\n\033[1;36m==>\033[0m \033[1m{banner}\033[0m")

    def finish(self) -> None:
        """Mark the entire process as complete."""
        _set_terminal_title(f"Quark {self._label} bootstrap — done")
        print(f"\n\033[1;32m==>\033[0m \033[1mBootstrap complete "
              f"[{self._total}/{self._total}]\033[0m")


def warn(message: str) -> None:
    """Print a warning that survives a wall of build output."""
    print(f"\n{'!' * 66}")
    for line in message.splitlines():
        print(f"! {line}")
    print(f"{'!' * 66}\n")


# ──────────────────────────────────────────────────────────────────────
# Spack helpers  (always uses a private, local clone — never the user's)
# ──────────────────────────────────────────────────────────────────────

def _local_spack_bin(layout: Layout) -> Path:
    """Return the path to the local Spack binary."""
    return layout.src / "spack" / "bin" / "spack"


def ensure_spack(layout: Layout) -> None:
    """Clone a private Spack into ``<prefix>/src/spack`` if not already present.

    We never use a system or user Spack installation — every Spack
    command executed by this script goes through the local clone so
    the build is fully self-contained and reproducible.
    """
    spack_bin = _local_spack_bin(layout)
    if spack_bin.exists():
        print(f"Local Spack already present at {spack_bin}")
        return

    print("\nInstalling a local Spack clone …")
    ensure_dir(layout.src)
    run("git clone --depth=1 https://github.com/spack/spack.git", cwd=layout.src)
    if not spack_bin.exists():
        raise RuntimeError(f"Spack clone succeeded but {spack_bin} does not exist.")
    print(f"Local Spack installed: {spack_bin}")


def spack_install(spec: str, layout: Layout, *, jobs: str = NJOBS) -> Path:
    """Install a Spack spec using the local Spack and return its prefix."""
    run([str(_local_spack_bin(layout)), "install", f"-j{jobs}", spec])
    return spack_prefix(spec, layout)


def spack_prefix(spec: str, layout: Layout) -> Path:
    """Return the install prefix of an already-installed Spack spec."""
    return Path(capture([str(_local_spack_bin(layout)), "location", "-i", spec]))


def spack_link_into(spec: str, layout: Layout, *, jobs: str = NJOBS) -> Path:
    """Install *spec* with the local Spack and symlink artifacts into ``deps``.

    This keeps a single unified prefix for a backend's configure step while
    letting Spack manage the actual build.

    Libraries from both ``lib/`` and ``lib64/`` in the Spack prefix are
    symlinked into ``deps/lib/`` so that ``--with-*=PREFIX`` flags (which
    always look in ``PREFIX/lib/``) work correctly.
    """
    pfx = spack_install(spec, layout, jobs=jobs)

    # Map Spack sub-directories to their destination under deps.
    # Crucially, lib64/ is merged into lib/ so a backend can find everything.
    DIR_MAP: dict[str, str] = {
        "lib":     "lib",
        "lib64":   "lib",       # ← redirect into lib/
        "include": "include",
        "bin":     "bin",
        "share":   "share",
    }

    for src_sub, dst_sub in DIR_MAP.items():
        src_dir = pfx / src_sub
        if not src_dir.exists(): continue
        dst_dir = ensure_dir(layout.deps / dst_sub)
        for item in src_dir.iterdir():
            dst = dst_dir / item.name
            if dst.exists() or dst.is_symlink(): dst.unlink()
            dst.symlink_to(item)
    return pfx


# Mapping from our internal library names to Spack spec strings.
SPACK_SPECS: dict[str, str] = {
    "gmp":        "gmp",
    "mpfr":       "mpfr",
    "fftw":       "fftw ~mpi precision=float,double",
    "openssl":    "openssl",
    "hdf5":       "hdf5 +cxx ~mpi",
    "lime":       "c-lime",
    "libunwind":  "libunwind",
    "qmp":        "qmp",
    "qio":        "qio",
}


def build_or_spack(
    lib_name: str,
    build_fn,
    build_args: tuple,
    layout: Layout,
    *,
    use_spack: bool = False,
    jobs: str = NJOBS,
) -> None:
    """Try *build_fn*; on failure (or if *use_spack*) fall back to Spack."""
    spec = SPACK_SPECS.get(lib_name, lib_name)

    if use_spack:
        print(f"\n--use-spack: installing {lib_name} via Spack ({spec})")
        spack_link_into(spec, layout, jobs=jobs)
        return

    try: build_fn(*build_args)
    except (subprocess.CalledProcessError, RuntimeError) as exc:
        warn(f"Source build of {lib_name} failed: {exc}\n"
             f"Falling back to Spack ({spec}) …")
        ensure_spack(layout)
        spack_link_into(spec, layout, jobs=jobs)


def lib_installed(prefix: Path, libname: str) -> bool:
    """Return True if *libname* (e.g. ``libgmp``) exists under *prefix*.

    Checks for static (``.a``) and shared (``.so``) libraries in both
    ``lib/`` and ``lib64/`` so that source-built *and* Spack-installed
    libraries are detected equally.
    """
    for libdir in ("lib", "lib64"):
        for ext in (".a", ".so", ".dylib"):
            if (prefix / libdir / f"{libname}{ext}").exists(): return True
    return False


# ──────────────────────────────────────────────────────────────────────
# Compiler resolution
# ──────────────────────────────────────────────────────────────────────

LLVM_VERSION = "18.1.8"


def _find_system_compiler() -> tuple[str, str]:
    """Return the best available system C/C++ compiler as (cc, cxx)."""
    if which("gcc") and which("g++"): return "gcc", "g++"
    if which("cc") and which("c++"): return "gcc", "g++"  # 'cc' is almost always gcc on Linux
    return "gcc", "g++"  # hopeful default


def _install_prebuilt_llvm(layout: Layout) -> Path:
    """Download a prebuilt LLVM/Clang release.  Returns the prefix containing bin/clang."""
    arch = {"x64": "X64", "arm64": "ARM64"}[host_arch()]
    src = layout.source("llvm")

    # Already extracted from a previous run?
    for d in src.iterdir():
        if d.is_dir() and (d / "bin" / "clang").exists(): return d

    tarball_name = f"LLVM-{LLVM_VERSION}-Linux-{arch}.tar.xz"
    url = (f"https://github.com/llvm/llvm-project/releases/"
           f"download/llvmorg-{LLVM_VERSION}/{tarball_name}")
    tarball = src / tarball_name

    if not tarball.exists(): download(url, tarball)
    run(f"tar xf {tarball_name}", cwd=src)

    # Scan for the extracted directory (name may vary across releases)
    for d in src.iterdir():
        if d.is_dir() and (d / "bin" / "clang").exists(): return d

    raise RuntimeError("Extracted LLVM tarball but could not find bin/clang in any subdirectory.")


def _prepend_to_path(bindir: Path) -> None:
    """Prepend *bindir* to PATH for this process and all children."""
    os.environ["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")


def _set_compiler_env(
    cc: str,
    cxx: str,
    layout: Layout,
    *,
    extra_path: str | None = None,
) -> None:
    """Persist CC/CXX in ``os.environ`` and write ``<prefix>/compiler.env``
    so that a backend's configure step picks up the same compiler."""
    os.environ["CC"] = cc
    os.environ["CXX"] = cxx

    env_file = layout.root / "compiler.env"
    with open(env_file, "w") as f:
        f.write("# Auto-generated by Quark bootstrap — do not edit\n")
        if extra_path: f.write(f'export PATH="{extra_path}:${{PATH}}"\n')
        f.write(f'export CC="{cc}"\n')
        f.write(f'export CXX="{cxx}"\n')
    print(f"Wrote {env_file}")


def ensure_compiler(
    layout: Layout,
    *,
    no_llvm: bool = False,
    jobs: str = NJOBS,
) -> tuple[str, str]:
    """Resolve C/C++ compilers.  Returns ``(cc, cxx)``.

    Fallback chain (unless *no_llvm*):

    1. User's ``clang`` / ``clang++`` already on ``PATH``
    2. Download a prebuilt LLVM release into ``<prefix>/src/llvm/``
    3. Install LLVM via the local Spack clone
    4. System default compilers (``gcc`` / ``g++``)
    """
    if no_llvm:
        cc, cxx = _find_system_compiler()
        print(f"--no-llvm: using system compilers: {cc} / {cxx}")
        _set_compiler_env(cc, cxx, layout)
        return cc, cxx

    # 1. User's clang on PATH
    if which("clang") and which("clang++"):
        print(f"Found clang on PATH: {which('clang')}")
        _set_compiler_env("clang", "clang++", layout)
        return "clang", "clang++"

    # 2. Prebuilt LLVM download
    try:
        print("\nclang not found on PATH — trying prebuilt LLVM download …")
        llvm_prefix = _install_prebuilt_llvm(layout)
        _prepend_to_path(llvm_prefix / "bin")
        print(f"Prebuilt LLVM ready: {llvm_prefix}")
        _set_compiler_env("clang", "clang++", layout,
                          extra_path=str(llvm_prefix / "bin"))
        return "clang", "clang++"
    except (subprocess.CalledProcessError, RuntimeError, OSError) as exc:
        print(f"Prebuilt LLVM install failed: {exc}")

    # 3. Spack
    try:
        print("\nTrying to install LLVM via Spack …")
        ensure_spack(layout)
        llvm_prefix = spack_install("llvm", layout, jobs=jobs)
        if (llvm_prefix / "bin" / "clang").exists():
            _prepend_to_path(llvm_prefix / "bin")
            print(f"Spack LLVM ready: {llvm_prefix}")
            _set_compiler_env("clang", "clang++", layout,
                              extra_path=str(llvm_prefix / "bin"))
            return "clang", "clang++"
    except (subprocess.CalledProcessError, RuntimeError) as exc:
        print(f"Spack LLVM install failed: {exc}")

    # 4. Fallback to system defaults
    cc, cxx = _find_system_compiler()
    warn(f"Could not install LLVM/Clang.\n"
         f"Falling back to system compilers: {cc} / {cxx}")
    _set_compiler_env(cc, cxx, layout)
    return cc, cxx


# ──────────────────────────────────────────────────────────────────────
# Nim toolchain
# ──────────────────────────────────────────────────────────────────────

# Quark's minimum is pinned in quark.nimble; keep this at or above it.
NIM_VERSION = "2.2.8"


def install_nim(layout: Layout, *, version: str = NIM_VERSION) -> Path:
    """Download a prebuilt Nim into ``<prefix>/nim`` and return the ``nim`` binary.

    Binaries are symlinked into ``<prefix>/nim/bin`` so that Nim resolves its
    standard library from the extracted tarball's own ``../lib`` directory.
    """
    nim_bin = layout.nim / "bin" / "nim"
    if nim_bin.exists():
        print(f"Nim already installed: {nim_bin}")
        return nim_bin

    tarball = f"nim-{version}-linux_{host_arch()}.tar.xz"
    url = f"https://nim-lang.org/download/{tarball}"
    src = layout.source("nim")
    if not (src / tarball).exists(): download(url, src / tarball)
    run(f"tar xf {tarball}", cwd=src)

    nim_dir = src / f"nim-{version}"
    if not (nim_dir / "bin" / "nim").exists():
        raise RuntimeError(f"Extracted {tarball} but {nim_dir}/bin/nim is missing.")

    ensure_dir(layout.nim / "bin")
    for item in (nim_dir / "bin").iterdir():
        dest = layout.nim / "bin" / item.name
        if dest.exists() or dest.is_symlink(): dest.unlink()
        dest.symlink_to(item.resolve())

    print(f"Nim {version} installed to {layout.nim} (symlinked from {nim_dir})")
    return nim_bin


def resolve_nim(layout: Layout, *, skip: bool = False, version: str = NIM_VERSION) -> Path:
    """Return the Nim binary to use: an existing local one, ``$NIM``, PATH, or a fresh install."""
    local_nim = layout.nim / "bin" / "nim"
    if local_nim.exists(): return local_nim

    if skip:
        env_nim = os.environ.get("NIM", "")
        if env_nim and Path(env_nim).exists(): return Path(env_nim).resolve()
        found = which("nim")
        if found:
            print(f"--skip-nim: using Nim on PATH: {found}")
            return Path(found).resolve()
        raise RuntimeError("--skip-nim was given but no nim was found in $NIM or on PATH.")

    return install_nim(layout, version=version)


# ──────────────────────────────────────────────────────────────────────
# Manifest — the handoff from bootstrap to configure
# ──────────────────────────────────────────────────────────────────────

def write_manifest(layout: Layout, backend: str, entry: dict,
                   *, nim: Path | None = None) -> Path:
    """Record what this bootstrap run produced, merging with earlier runs.

    Bootstrapping a second backend must not erase the first, so each backend
    owns one key under ``backends`` and the rest of the file is rewritten.
    ``configure`` reads this file to discover what is available on the machine.
    *nim* is the Nim actually used, which is not always the one under this
    prefix: ``--skip-nim`` deliberately uses the system toolchain instead.
    """
    data: dict = {"version": 1, "prefix": str(layout.root), "backends": {}}
    if layout.manifest.exists():
        try:
            existing = json.loads(layout.manifest.read_text())
            if isinstance(existing, dict):
                data.update(existing)
                data.setdefault("backends", {})
        except json.JSONDecodeError:
            warn(f"{layout.manifest} is not valid JSON; rewriting it.")
            data["backends"] = {}

    data["version"] = 1
    data["prefix"] = str(layout.root)
    if nim is not None:
        data["nim"] = str(nim)
    data["backends"][backend] = entry

    layout.manifest.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    print(f"Wrote manifest: {layout.manifest}")
    return layout.manifest


# ──────────────────────────────────────────────────────────────────────
# Shared command-line options
# ──────────────────────────────────────────────────────────────────────

def add_common_arguments(p: argparse.ArgumentParser) -> None:
    """Add the option groups every backend bootstrap script shares."""
    loc = p.add_argument_group("install location")
    loc.add_argument("--prefix", metavar="DIR", default=str(QUARK_ROOT / "local"),
                     help="Directory every artifact is installed under "
                          "(default: <quark>/local)")

    dep = p.add_argument_group("dependency control")
    dep.add_argument("--skip-deps", action="store_true",
                     help="Do not build any dependencies; assume they are installed elsewhere.")
    dep.add_argument("--use-spack", action="store_true",
                     help="Install all dependencies via a private Spack clone instead of "
                          "building from source. Without this flag, Spack is only used as a "
                          "fallback when a source build fails.")

    tc = p.add_argument_group("toolchain")
    tc.add_argument("--no-llvm", action="store_true",
                    help="Do not attempt to install or use LLVM/Clang; use the default "
                         "system compiler (typically GCC) instead.")
    tc.add_argument("--skip-nim", action="store_true",
                    help="Do not install Nim; use $NIM or the nim found on PATH.")
    tc.add_argument("--nim-version", metavar="VERSION", default=NIM_VERSION,
                    help=f"Nim version to install (default: {NIM_VERSION})")

    bc = p.add_argument_group("build control")
    bc.add_argument("--jobs", "-j", default=NJOBS, metavar="N",
                    help=f"Parallel make jobs (default: {NJOBS})")
