"""
configure.py — turn what bootstrap installed into Quark's build configuration.

build: build/configure.py
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

Usage
-----
    python3 build/configure.py [OPTIONS]

Normally invoked through the top-level ``configure`` driver:

    ./configure [OPTIONS]

Configure reads back how each backend was *actually* built rather than
deriving any of it a second time. Every backend already records its own build:

    Grid    bin/grid-config, which reports its compile and link flags
    QEX     qexconfig.nims, holding every compiler, SIMD, and library setting
    QUDA    CMakeCache.txt, the record of what CMake settled on

Those records, together with ``bootstrap.json``, become one file:

    <prefix>/quark.conf

which is the only thing Quark itself reads. `src/quark/build/configuration.nim`
finds it at compile time and `src/quark/backend/backend.nim` turns the selected
backend's entry into passC and passL pragmas, which is what lets an installed
Quark be imported by an ordinary Nim file with no build system of its own.

Configure also writes the pieces an in-repository build needs: ``nim.cfg`` for
the flags Nim wants on the command line rather than in pragmas, and a
``Makefile`` that compiles any one program under the source tree by name.

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
import os
import shlex
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from build.common import QUARK_ROOT, ensure_dir, warn, which  # noqa: E402

BACKENDS = ["grid", "qex", "quda"]


# ──────────────────────────────────────────────────────────────────────
# A configured backend
# ──────────────────────────────────────────────────────────────────────

class BackendConfig:
    """One backend's settings, as read back from how it was built.

    ``passC`` and ``passL`` travel with Quark's source as pragmas, so they
    reach any project that imports Quark. ``nimFlags`` are the settings Nim
    only accepts on its command line — search paths, defines, and environment
    variables — so they reach an in-repository build through ``nim.cfg``.
    """

    def __init__(self, name: str, prefix: str) -> None:
        self.name = name
        self.prefix = prefix
        self.language = ""
        self.passC: list[str] = []
        self.passL: list[str] = []
        self.nimFlags: list[str] = []
        self.extra: dict[str, str] = {}

    def note(self, key: str, value: str) -> None:
        """Record a fact worth keeping even though it emits no flag."""
        if value:
            self.extra[key] = value

    def add_library_path(self, directory: str) -> None:
        """Link against a directory and record it for the runtime loader too.

        Without an rpath a shared backend library is found at link time and
        missing at run time, which is a confusing way to discover the problem.
        """
        if not directory: return
        self.passL.append(f"-L{directory}")
        self.passL.append(f"-Wl,-rpath,{directory}")

    @staticmethod
    def _dedupe(flags: list[str]) -> list[str]:
        """Drop repeated search paths, keeping the first of each.

        Two dependencies installed into one prefix contribute the same -I, -L,
        and -rpath repeatedly. Library flags are left alone, since repeating
        one can be deliberate and their order is what the linker acts on.
        """
        seen: set[str] = set()
        result: list[str] = []
        for flag in flags:
            if flag.startswith(("-I", "-L", "-Wl,-rpath,")):
                if flag in seen: continue
                seen.add(flag)
            result.append(flag)
        return result

    def as_section(self) -> str:
        self.passC = self._dedupe(self.passC)
        self.passL = self._dedupe(self.passL)
        lines = [f"[{self.name}]", f"prefix   = {self.prefix}"]
        if self.language:
            lines.append(f"language = {self.language}")
        if self.passC:
            lines.append(f"passC    = {' '.join(self.passC)}")
        if self.passL:
            lines.append(f"passL    = {' '.join(self.passL)}")
        for flag in self.nimFlags:
            lines.append(f"nimFlag  = {flag}")
        for key in sorted(self.extra):
            lines.append(f"{key} = {self.extra[key]}")
        return "\n".join(lines)


# ──────────────────────────────────────────────────────────────────────
# Grid
# ──────────────────────────────────────────────────────────────────────

def _grid_config(config: Path, *args: str) -> str:
    """Ask grid-config a question, returning the empty string if it cannot."""
    try:
        return subprocess.check_output([str(config), *args], text=True,
                                       stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, OSError):
        return ""


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

    seen: set[str] = set()
    for token in shlex.split(_grid_config(config, "--ldflags")) + \
                 shlex.split(_grid_config(config, "--libs")):
        if token.startswith("-L"):
            directory = token[2:]
            if directory not in seen:
                seen.add(directory)
                cfg.add_library_path(directory)
        else:
            cfg.passL.append(token)

    summary = _grid_config(config, "--summary")
    for line in summary.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].upper().startswith("SIMD"):
            cfg.note("simd", parts[-1])

    cfg.note("config", str(config))
    cfg.note("accelerator", entry.get("accelerator", ""))
    return cfg


# ──────────────────────────────────────────────────────────────────────
# QEX
# ──────────────────────────────────────────────────────────────────────

def read_qexconfig(path: Path) -> dict[str, str]:
    """Read the settings out of a ``qexconfig.nims``.

    The file is Nim source, but every line configure needs is a plain
    assignment. Values are string literals, integers, sequence literals, or a
    reference to a setting assigned earlier (QEX writes ``ld = cc``), so a
    reference is resolved against what has been read so far. Anything less
    simple is left alone rather than half-understood.
    """
    settings: dict[str, str] = {}

    def evaluate(expression: str) -> str | None:
        """Evaluate one qexconfig value, or return None if it is not simple.

        Values are string literals, integers, references to a setting assigned
        earlier, or those joined with Nim's `&`, which is how QEX writes
        `ld = cc` and `ldflags = cflagsAlways & " -ldl"`. Anything richer is
        reported as unresolved rather than passed along half-understood, since
        a Nim expression handed to a compiler as a flag is worse than a
        missing flag.
        """
        parts: list[str] = []
        for term in expression.split("&"):
            term = term.strip()
            if len(term) >= 2 and term.startswith('"') and term.endswith('"'):
                parts.append(term[1:-1])
            elif term in settings:
                parts.append(settings[term])
            elif term.isdigit():
                parts.append(term)
            else:
                return None
        return "".join(parts)

    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or "=" not in line: continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not key.isidentifier(): continue
        resolved = evaluate(value)
        settings[key] = value if resolved is None else resolved
        if resolved is None:
            settings.setdefault(UNRESOLVED, "")
            settings[UNRESOLVED] += (" " if settings[UNRESOLVED] else "") + key
    return settings


# Key under which read_qexconfig records the settings it could not evaluate.
UNRESOLVED = "__unresolved__"


def configure_qex(prefix: Path, entry: dict, args: argparse.Namespace) -> BackendConfig:
    """Read QEX's build back out of the qexconfig.nims its configure wrote."""
    cfg = BackendConfig("qex", str(prefix))

    config = Path(entry.get("config") or (prefix / "qexconfig.nims"))
    if not config.exists():
        raise RuntimeError(
            f"QEX's build settings live in {config}, which does not exist.\n"
            f"Re-run './bootstrap --backend qex', or pass --qex-prefix=PATH."
        )
    settings = read_qexconfig(config)
    # 'envs' and 'nimargs' are Nim sequence literals rather than plain values,
    # and are read by _nim_sequence below; they are not a shortfall.
    unresolved = [key for key in settings.pop(UNRESOLVED, "").split()
                  if key not in ("envs", "nimargs")]
    if unresolved:
        warn(f"These settings in {config} are not plain values and were left "
             f"out of the configuration:\n  {', '.join(unresolved)}\n"
             f"Set them explicitly with ./configure if a build needs them.")

    cfg.language = settings.get("ccDef", "cc")

    # QEX's source has to be on Nim's search path, since Quark's QEX adapter
    # compiles against QEX's own modules rather than a compiled library.
    source = Path(entry.get("source") or (prefix / "qex"))
    qex_src = source / "src"
    if qex_src.exists():
        cfg.nimFlags.append(f"--path:{qex_src}")
    else:
        warn(f"QEX's source was expected at {qex_src} but is not there.\n"
             f"Quark's QEX adapter compiles against QEX's own modules, so a "
             f"build against this QEX will not find them.")

    # QMP and QIO are C libraries QEX links against. QEX passes their
    # locations to its own modules as defines, and those modules emit the
    # link flags, so both forms are recorded.
    # QMP and QIO reach the build as defines rather than as link flags:
    # QEX's own comms and I/O modules read these and emit the -L and -l flags
    # themselves, so emitting them here too would only duplicate QEX's link
    # line. The include paths are kept, being harmless and occasionally useful
    # to Quark's own C interop.
    for key in ("qmpDir", "qioDir"):
        directory = settings.get(key, "")
        if not directory: continue
        cfg.passC.append(f"-I{directory}/include")
        cfg.nimFlags.append(f"-d:{key}={directory}")

    # Optional libraries QEX was configured against.
    for key in ("qudaDir", "cudaLibDir", "cudaMathLibDir", "nvhpcDir",
                "primmeDir", "chromaDir", "gridDir"):
        value = settings.get(key, "")
        if value:
            cfg.nimFlags.append(f"-d:{key}={value}")
            cfg.note(key, value)

    # QEX links against MPI through compiler wrappers, so the wrapper has to
    # be the compiler Nim drives. QEX's configBase.nims makes exactly this
    # translation from the same settings; it is repeated here so that a Quark
    # build compiles QEX the way QEX compiles itself.
    ccType = settings.get("ccType", "gcc")
    cfg.nimFlags.append(f"--cc:{ccType}")
    for key, flag in (("cc", "exe"),
                      ("ld", "linkerexe"),
                      ("cpp", "cpp.exe"),
                      ("ldpp", "cpp.linkerexe"),
                      ("cflagsAlways", "options.always"),
                      ("cflagsDebug", "options.debug"),
                      ("cflagsSpeed", "options.speed"),
                      ("ldflags", "options.linker"),
                      ("cppflagsAlways", "cpp.options.always"),
                      ("cppflagsDebug", "cpp.options.debug"),
                      ("cppflagsSpeed", "cpp.options.speed"),
                      ("ldppflags", "cpp.options.linker")):
        value = settings.get(key, "")
        if value and key not in unresolved:
            cfg.nimFlags.append(f"--{ccType}.{flag}:{value}")

    # QEX's threading and memory model are not optional: its own build sets
    # these, and code compiled against it has to agree.
    cfg.nimFlags.extend(["--threads:on", "--tlsEmulation:off", "--mm:refc"])

    # SIMD selection reaches QEX as one define per instruction set, and the
    # vector length as an environment variable, exactly as QEX's own
    # configBase.nims does it.
    simd = settings.get("simd", "")
    for instruction_set in (s.strip() for s in simd.split(",")):
        if instruction_set in ("QPX", "SSE", "AVX", "AVX512"):
            cfg.nimFlags.append(f"-d:{instruction_set}")
    vlen = settings.get("vlen", "")
    if vlen:
        cfg.nimFlags.append(f"--putenv:VLEN={vlen}")
        cfg.note("vlen", vlen)

    # Environment variables and extra Nim arguments QEX bakes into a build,
    # including the '-d:Backend=...' that selects its accelerator.
    for value in _nim_sequence(settings.get("envs", "")):
        cfg.nimFlags.append(f"--putenv:{value}")
    for value in _nim_sequence(settings.get("nimargs", "")):
        cfg.nimFlags.append(value)

    cfg.note("config", str(config))
    cfg.note("source", str(source))
    cfg.note("simd", simd)
    cfg.note("accelerator", entry.get("accelerator", ""))
    return cfg


def _nim_sequence(literal: str) -> list[str]:
    """Return the strings in a Nim sequence literal such as ``@["a", "b"]``."""
    literal = literal.strip()
    if not literal.startswith("@["): return []
    inner = literal[2:].rstrip()
    if inner.endswith("]"): inner = inner[:-1]
    values: list[str] = []
    for part in inner.split('","'):
        value = part.strip().strip(",").strip().strip('"')
        if value: values.append(value)
    return values


# ──────────────────────────────────────────────────────────────────────
# QUDA
# ──────────────────────────────────────────────────────────────────────

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
    if cache.exists():
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
    if not cache.exists(): return ""
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


CONFIGURERS = {"grid": configure_grid, "qex": configure_qex, "quda": configure_quda}

# Keys configure derives itself. Everything else bootstrap recorded is copied
# into the backend's section as provenance, so that what a program was built
# against can be printed at compile time, and so that a fact bootstrap learns
# to record in future shows up here without configure being taught about it.
RESERVED_KEYS = {"prefix", "language", "passC", "passL", "nimFlags"}


def carry_provenance(cfg: BackendConfig, entry: dict) -> None:
    """Copy what bootstrap recorded about a backend into its section."""
    for key in sorted(entry):
        if key in RESERVED_KEYS or key in cfg.extra:
            continue
        value = entry[key]
        if isinstance(value, str) and value:
            cfg.extra[key] = value


# ──────────────────────────────────────────────────────────────────────
# Generated files
# ──────────────────────────────────────────────────────────────────────

def write_quark_conf(path: Path, configs: list[BackendConfig],
                     default_backend: str, nim: str,
                     globals: dict[str, str] | None = None) -> None:
    """Write the configuration Quark's own source reads at compile time."""
    lines = [
        "# Quark build configuration",
        "#",
        "# Written by ./configure from what ./bootstrap installed. Re-run",
        "# configure rather than editing this file, unless a backend was built",
        "# by hand, in which case editing it is exactly the intended use.",
        "#",
        "# Read at compile time by src/quark/build/configuration.nim.",
        "",
    ]
    if default_backend:
        lines.append(f"default.backend = {default_backend}")
    if nim:
        lines.append(f"nim = {nim}")
    for key in sorted(globals or {}):
        if (globals or {})[key]:
            lines.append(f"{key} = {(globals or {})[key]}")
    for cfg in configs:
        lines += ["", cfg.as_section()]
    path.write_text("\n".join(lines) + "\n")
    print(f"-- Wrote {path}")


MAKEFILE_NIMS = '''#[
Build tasks

Written by ./configure. Re-run configure rather than editing.

Compiles one program under the Quark source tree by name, the way QEX and
Grim build individual scripts: the name is searched for rather than spelled
out, so a target is named the way it is spoken about.

The flags come from quark.conf, the same file Quark's own source reads at
compile time, so a program built here and a program built by an installed
Quark are built the same way.
]#

import std/[os, strutils]

const
  quarkRoot = "@QUARK_ROOT@"
  buildDir = "@BUILD_DIR@"
  nimExe = "@NIM@"
  quarkConf = "@QUARK_CONF@"
  defaultBackend = "@DEFAULT_BACKEND@"
  binDir = buildDir / "bin"
  cacheDir = buildDir / "nimcache"
  searchDirs = ["src", "tests", "oracle", "examples"]

proc settings(backend, key: string): seq[string] =
  ## Return every value `key` has in one backend's section of quark.conf.
  ##
  ## A key may appear more than once: 'nimFlag' does, one flag per line,
  ## because a compiler flag list contains spaces and so cannot be recovered
  ## from a single whitespace-joined field.
  if not fileExists(quarkConf): return
  var current = ""
  for raw in readFile(quarkConf).splitLines:
    let line = raw.strip
    if line.len == 0 or line.startsWith("#"): continue
    if line.startsWith("[") and line.endsWith("]"):
      current = line[1 ..< line.high].strip
      continue
    if current != backend: continue
    let sep = line.find('=')
    if sep < 0: continue
    if line[0 ..< sep].strip == key:
      result.add line[sep + 1 .. line.high].strip

proc setting(backend, key: string): string =
  ## Return one backend's value for `key` from quark.conf, or "".
  let values = settings(backend, key)
  if values.len > 0: values[^1] else: ""

proc quoted(flag: string): string =
  ## Quote a flag for the shell, since a flag may carry a list of C flags.
  if flag.contains(' ') or flag.contains('"'): "'" & flag & "'" else: flag

proc targets(): seq[string] =
  ## Every compilable program under the searched directories.
  for dir in searchDirs:
    let full = quarkRoot / dir
    if not dirExists(full): continue
    for entry in walkDirRec(full):
      if entry.endsWith(".nim"):
        result.add entry

proc find(name: string): string =
  ## Resolve a target name to exactly one source file.
  ##
  ## A name matches on the file's stem or on any tail of its path, so both
  ## 'oracleA' and 'oracle/oracleA' name the same program. More than one
  ## match is an error rather than a guess.
  var matches: seq[string]
  for candidate in targets():
    let (_, stem, _) = candidate.splitFile
    if stem == name or candidate.endsWith(name & ".nim"):
      matches.add candidate
  if matches.len == 1: return matches[0]
  if matches.len == 0:
    echo "No target matches '", name, "'."
    echo "Run 'make list' to see what is available."
    quit(1)
  echo "'", name, "' matches more than one target:"
  for m in matches: echo "  ", m.relativePath(quarkRoot)
  echo "Name more of the path to choose one."
  quit(1)

task list, "list the programs make can build":
  for candidate in targets():
    echo "  ", candidate.relativePath(quarkRoot)

task clean, "remove built programs and the compile cache":
  rmDir cacheDir
  rmDir binDir

task build, "compile one program by name":
  # Arguments after the task name: flags first, then the target name last.
  var args: seq[string]
  for i in 3 .. paramCount():
    args.add paramStr(i)
  if args.len == 0:
    echo "Usage: make <target> [FLAGS...]"
    echo "Run 'make list' to see what is available."
    quit(1)

  let name = args[^1]
  let source = find(name)

  var backend = defaultBackend
  var chosenExplicitly = false
  for a in args:
    if a.startsWith("-d:backend="):
      backend = a["-d:backend=".len .. ^1]
      chosenExplicitly = true

  # A release build is the default. An unoptimised lattice program is only
  # useful for debugging, so optimisation is opted out of rather than into.
  # Any explicit choice on the command line wins, including one arriving
  # through ARGS, which is why this is decided here rather than in the
  # Makefile.
  var optimisationChosen = false
  for a in args:
    if a in ["-d:release", "-d:danger", "-d:debug"] or a.startsWith("--opt:"):
      optimisationChosen = true

  if backend.len > 0 and setting(backend, "prefix").len == 0:
    echo "Warning: '", backend, "' is not configured in ", quarkConf
    echo "  Building without its compiler and linker flags. Run ./configure"
    echo "  after bootstrapping it, or pick a backend that is configured."

  # Quark compiles as C or C++ depending on what the backend is written in.
  let language = if setting(backend, "language") == "cpp": "cpp" else: "c"

  mkDir binDir
  var command = nimExe & " " & language
  command &= " --path:" & quarkRoot / "src"
  command &= " --nimcache:" & cacheDir / name.splitFile.name
  if backend.len > 0 and not chosenExplicitly:
    command &= " -d:backend=" & backend
  if not optimisationChosen:
    command &= " -d:release"

  # Search paths, defines, compiler executables, and environment variables
  # cannot travel in Quark's source the way passC and passL do, so they are
  # applied here.
  for flag in settings(backend, "nimFlag"):
    command &= " " & quoted(flag)

  for a in args[0 ..< args.high]:
    command &= " " & a
  command &= " -o:" & binDir / name.splitFile.name
  command &= " " & source

  echo "BUILD: ", command
  exec command
'''

MAKEFILE = '''# Quark
#
# Written by ./configure. Re-run configure rather than editing.
#
# Usage:
#   make <target>              compile one program by name, optimised
#   make <target> DEBUG=1      compile it unoptimised, for debugging
#   make list                  show every program make can build
#   make clean                 remove built programs and the compile cache
#
# Targets are searched for by name under src, tests, oracle, and examples, so
# 'make oracleA' finds oracle/oracleA.nim.

NIM = @NIM@
NIMS = @NIMS@

FLAGS =

# A release build is the default, so none of these need to be given to get an
# optimised program. DEBUG turns optimisation off; DANGER goes further than
# release and removes the runtime checks release keeps.

ifdef DEBUG
FLAGS += --opt:none --debugger:native --lineDir:on
endif

ifdef DANGER
FLAGS += -d:danger
endif

ifdef RELEASE
FLAGS += -d:release
endif

ifdef BACKEND
FLAGS += -d:backend=$(BACKEND)
endif

ifdef VERBOSE
FLAGS += -d:quarkVerbose
endif

.PHONY: help list clean

help:
	@echo ""
	@echo "Quark"
	@echo ""
	@echo "  make <target>            compile one program by name"
	@echo "  make list                show every program make can build"
	@echo "  make clean               remove built programs and the cache"
	@echo ""
	@echo "Options:"
	@echo "  BACKEND=grid|qex|quda    choose the backend (default: @DEFAULT_BACKEND@)"
	@echo "  VERBOSE=1                report the build configuration while compiling"
	@echo "  DEBUG=1                  unoptimised, with native debugger and line info"
	@echo "  DANGER=1                 optimised with runtime checks removed"
	@echo "  RELEASE=1                optimised (the default; no need to pass it)"
	@echo "  ARGS=\\"...\\"              extra flags for Nim"
	@echo ""

list:
	@$(NIM) list $(NIMS)

clean:
	@$(NIM) clean $(NIMS)

BUILD_TARGETS := $(filter-out help list clean,$(MAKECMDGOALS))

ifneq ($(BUILD_TARGETS),)
$(BUILD_TARGETS): build-impl
	@true

.PHONY: build-impl
build-impl:
	@$(NIM) build $(NIMS) $(FLAGS) $(ARGS) $(BUILD_TARGETS)
endif
'''


def _as_switch(flag: str) -> str:
    """Render one Nim command-line flag as a NimScript `switch` call.

    A config file cannot take command-line flags, so each one is translated:
    `--key:value` becomes switch("key", "value"), `-d:x=y` becomes
    switch("define", "x=y"), and a bare `--key` becomes switch("key").
    """
    def call(name: str, value: str | None = None) -> str:
        if value is None:
            return f'  switch({name!r})'.replace("'", '"')
        return f'  switch({name!r}, {value!r})'.replace("'", '"')

    if flag.startswith("-d:"):
        return call("define", flag[3:])
    if flag.startswith("--"):
        name, separator, value = flag[2:].partition(":")
        return call(name, value) if separator else call(name)
    # Anything else is passed through as a define, which is what a bare
    # switch of this shape means to Nim.
    return call("define", flag.lstrip("-"))


QUARK_NIMS_HEADER = '''# Quark Nim configuration
#
# Written by ./configure. Re-run configure rather than editing.
#
# Include this from a project\'s config.nims to build against a Quark backend:
#
#     include "@SELF@"
#
# It applies the settings that cannot travel in Quark\'s own source, because
# Nim only accepts them on its command line: search paths, defines that a
# backend\'s own modules read, the compiler executables a backend links
# through, and environment variables. Compiler and linker flags are not
# repeated here - those travel with Quark\'s source as passC and passL
# pragmas, and reach any project that imports Quark.
#
# The backend is chosen the same way it is chosen in Quark itself, with
# -d:backend=NAME. With none given, the configured default applies.

const quarkBackend {.strdefine: "backend".} = "@DEFAULT_BACKEND@"

'''


def write_quark_nims(path: Path, configs: list[BackendConfig],
                     default_backend: str) -> None:
    """Write the Nim configuration a project outside this checkout includes."""
    lines = [QUARK_NIMS_HEADER
             .replace("@SELF@", str(path))
             .replace("@DEFAULT_BACKEND@", default_backend)]

    for cfg in configs:
        if not cfg.nimFlags:
            continue
        lines.append(f'when quarkBackend == "{cfg.name}":')
        lines.extend(_as_switch(flag) for flag in cfg.nimFlags)
        lines.append("")

    if not any(cfg.nimFlags for cfg in configs):
        lines.append("# No backend needs settings of this kind; a project that")
        lines.append("# imports Quark needs nothing beyond the package itself.")
        lines.append("")

    path.write_text("\n".join(lines))
    print(f"-- Wrote {path}")


def write_make_files(quark_root: Path, build_dir: Path, nim: str,
                     default_backend: str, quark_conf: Path) -> None:
    """Write the Makefile and the build script it hands its work to.

    Both go in the build directory, along with everything a build produces,
    so that the source tree stays clean and several build directories can
    exist against one checkout. `make` is run from there.
    """
    nims = build_dir / "Makefile.nims"
    nims.write_text(
        MAKEFILE_NIMS
        .replace("@QUARK_ROOT@", str(quark_root))
        .replace("@BUILD_DIR@", str(build_dir))
        .replace("@NIM@", nim)
        .replace("@QUARK_CONF@", str(quark_conf))
        .replace("@DEFAULT_BACKEND@", default_backend))
    print(f"-- Wrote {nims}")

    makefile = build_dir / "Makefile"
    makefile.write_text(
        MAKEFILE
        .replace("@NIM@", nim)
        .replace("@NIMS@", str(nims))
        .replace("@DEFAULT_BACKEND@", default_backend or "none"))
    print(f"-- Wrote {makefile}")


def install_user_config(source: Path, nims: Path) -> Path:
    """Copy the configuration where an installed Quark looks for it.

    The Nim configuration goes alongside it, so that the line a project adds
    to its own config.nims has a stable path rather than one pointing into
    whichever build directory happened to produce it.
    """
    directory = ensure_dir(Path.home() / ".config" / "quark")
    destination = directory / "config"
    destination.write_text(source.read_text())
    print(f"-- Installed {destination}")

    user_nims = directory / "quark.nims"
    user_nims.write_text(nims.read_text().replace(str(nims), str(user_nims)))
    print(f"-- Installed {user_nims}")
    return user_nims


# ──────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────

EPILOG = """\
examples:
  # Configure everything bootstrap installed
  ./configure

  # Build somewhere else entirely
  ./configure --build-dir ~/builds/quark-avx2

  # Choose which backend an unqualified 'import quark' uses
  ./configure --backend qex

  # Make the configuration available to projects outside this checkout
  ./configure --user

  # Configure against backends built by hand, with no bootstrap manifest
  ./configure --grid-prefix /opt/grid --qex-prefix /opt/qex-build

  # Just show what would be written
  ./configure --show
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="configure",
        description="Turn what bootstrap installed into Quark's build configuration.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=EPILOG,
    )

    loc = p.add_argument_group("locations")
    loc.add_argument("--prefix", metavar="DIR", default=str(QUARK_ROOT / "local"),
                     help="Where bootstrap installed (default: <quark>/local)")
    loc.add_argument("--build-dir", metavar="DIR", default=None,
                     help="Directory the Makefile, its build script, and "
                          "everything a build produces go in "
                          "(default: the prefix)")
    loc.add_argument("--output", metavar="PATH", default=None,
                     help="Configuration file to write "
                          "(default: <build dir>/quark.conf)")
    loc.add_argument("--nim", metavar="PATH", default=None,
                     help="Nim compiler to build with (default: the one "
                          "bootstrap installed, else the nim on PATH)")

    sel = p.add_argument_group("backend selection")
    sel.add_argument("--backend", metavar="NAME", default=None,
                     help="Backend an 'import quark' with no -d:backend uses. "
                          "Defaults to the only configured backend when there "
                          "is exactly one.")
    sel.add_argument("--only", metavar="NAME", action="append",
                     help="Configure only this backend. Repeatable.")

    ovr = p.add_argument_group("backend prefixes (configure without a manifest)")
    ovr.add_argument("--grid-prefix", metavar="PATH",
                     help="Grid install prefix, containing bin/grid-config")
    ovr.add_argument("--qex-prefix", metavar="PATH",
                     help="QEX build directory, containing qexconfig.nims")
    ovr.add_argument("--quda-prefix", metavar="PATH",
                     help="QUDA install prefix, containing include/")
    ovr.add_argument("--cuda-lib-dir", metavar="DIR",
                     help="CUDA library directory, when QUDA's cache does not name one")

    out = p.add_argument_group("output")
    out.add_argument("--user", action="store_true",
                     help="Also install the configuration to "
                          "~/.config/quark/config, where a Quark installed "
                          "with nimble looks for it")
    out.add_argument("--no-make", action="store_true",
                     help="Do not write the Makefile and its build script")
    out.add_argument("--show", action="store_true",
                     help="Print the configuration instead of writing anything")

    return p


# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────

def load_manifest(prefix: Path) -> dict:
    """Read what bootstrap recorded, tolerating its absence."""
    manifest = prefix / "bootstrap.json"
    if not manifest.exists():
        return {}
    try:
        data = json.loads(manifest.read_text())
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{manifest} is not valid JSON: {exc}") from None
    print(f"-- Read {manifest}")
    return data if isinstance(data, dict) else {}


def resolve_nim(args: argparse.Namespace, prefix: Path, manifest: dict) -> str:
    """Return the Nim the generated build files should use."""
    if args.nim: return args.nim
    local_nim = prefix / "nim" / "bin" / "nim"
    if local_nim.exists(): return str(local_nim)
    recorded = manifest.get("nim", "")
    if recorded and Path(recorded).exists(): return recorded
    found = which("nim")
    if found: return found
    warn("No Nim compiler was found. The generated Makefile will not work "
         "until one is on PATH or --nim=PATH is given.")
    return "nim"


def collect(args: argparse.Namespace, prefix: Path,
            manifest: dict) -> list[BackendConfig]:
    """Configure every backend this machine has, in a stable order."""
    entries: dict[str, dict] = dict(manifest.get("backends", {}))

    # An explicit prefix configures a backend that no manifest mentions, which
    # is what makes a hand-built backend usable.
    for name in BACKENDS:
        override = getattr(args, f"{name}_prefix")
        if override:
            entry = dict(entries.get(name, {}))
            entry["prefix"] = override
            entry.pop("config", None)
            entries[name] = entry

    wanted = set(args.only) if args.only else None
    configs: list[BackendConfig] = []
    for name in BACKENDS:
        if name not in entries: continue
        if wanted is not None and name not in wanted: continue
        entry = entries[name]
        backend_prefix = Path(entry.get("prefix", ""))
        if not backend_prefix:
            warn(f"The manifest names {name} but records no prefix; skipping it.")
            continue
        try:
            cfg = CONFIGURERS[name](backend_prefix, entry, args)
            carry_provenance(cfg, entry)
            configs.append(cfg)
            print(f"-- Configured {name}: {backend_prefix}")
        except RuntimeError as exc:
            warn(f"Could not configure {name}:\n{exc}\nSkipping it.")
    return configs


def choose_default(args: argparse.Namespace,
                   configs: list[BackendConfig]) -> str:
    """Return the backend an unqualified 'import quark' should use."""
    names = [c.name for c in configs]
    if args.backend:
        chosen = args.backend.strip().lower().replace("-", " ").replace("_", " ")
        chosen = {"quantum expressions": "qex"}.get(chosen, chosen)
        if chosen not in BACKENDS:
            raise RuntimeError(
                f"'{args.backend}' names no backend. "
                f"Choose one of: {', '.join(BACKENDS)}.")
        if chosen not in names:
            warn(f"--backend {chosen} was asked for, but {chosen} is not "
                 f"configured on this machine. Recording it anyway; an "
                 f"unqualified 'import quark' will fail until it is built.")
        return chosen
    # With exactly one backend the choice is unambiguous, so make it. With
    # several, leaving it unset keeps the selection explicit rather than
    # arbitrary.
    return names[0] if len(names) == 1 else ""


def main() -> None:
    args = build_parser().parse_args()
    prefix = Path(args.prefix).resolve()
    quark_root = QUARK_ROOT

    manifest = load_manifest(prefix)
    if not manifest and not any(getattr(args, f"{n}_prefix") for n in BACKENDS):
        raise SystemExit(
            f"configure: nothing to configure.\n"
            f"       No manifest at {prefix / 'bootstrap.json'} and no "
            f"--grid-prefix, --qex-prefix, or --quda-prefix was given.\n"
            f"       Run './bootstrap --backend <name>' first.")

    configs = collect(args, prefix, manifest)
    if not configs:
        raise SystemExit(
            "configure: no backend could be configured.\n"
            "       The warnings above say why for each one.")

    default_backend = choose_default(args, configs)
    nim = resolve_nim(args, prefix, manifest)

    build_dir = Path(args.build_dir).resolve() if args.build_dir else prefix
    output = Path(args.output) if args.output else build_dir / "quark.conf"

    if args.show:
        lines = ([f"default.backend = {default_backend}"] if default_backend else []) \
                + [f"nim = {nim}"] + [""] \
                + [c.as_section() + "\n" for c in configs]
        print("\n".join(lines))
        return

    manifest_path = prefix / "bootstrap.json"
    global_settings = {
        "prefix": str(prefix),
        "bootstrap": str(manifest_path) if manifest_path.exists() else "",
        "configured": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    if args.build_dir:
        global_settings["build"] = str(build_dir)

    ensure_dir(build_dir)
    ensure_dir(output.parent)
    write_quark_conf(output, configs, default_backend, nim, global_settings)
    nims = build_dir / "quark.nims"
    write_quark_nims(nims, configs, default_backend)
    if not args.no_make:
        write_make_files(quark_root, build_dir, nim, default_backend, output)
    user_nims = install_user_config(output, nims) if args.user else None

    print(f"\n{'=' * 66}")
    print(f"Quark configured.")
    print(f"  backends   {', '.join(c.name for c in configs)}")
    print(f"  default    {default_backend or 'none; pass -d:backend=NAME'}")
    print(f"  config     {output}")
    if not args.no_make:
        print(f"  build in   {build_dir}")
    print("")
    if not args.no_make:
        print(f"  cd {build_dir}")
    print(f"  make list              show the programs make can build")
    print(f"  make <target>          compile one of them into bin/")
    print(f"  nimble install         install Quark as a package")
    if not args.user:
        print(f"  ./configure --user     let projects outside this checkout use it")
    if any(cfg.nimFlags for cfg in configs):
        print("")
        print("  A project outside this checkout that uses a backend needing")
        print("  search paths or compiler settings adds one line to its own")
        print("  config.nims:")
        print("")
        print(f'    include "{user_nims or nims}"')
    print(f"{'=' * 66}\n")


if __name__ == "__main__":
    try: main()
    except RuntimeError as exc:
        raise SystemExit(f"configure: {exc}")
