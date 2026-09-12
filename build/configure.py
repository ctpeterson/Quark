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
import re
import shlex
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from build.common import QUARK_ROOT, ensure_dir, warn, which  # noqa: E402

BACKENDS = ["grid", "qex", "quda"]


def canonical_backend(name: str) -> str:
    value = name.lower().replace("_", " ").replace("-", " ").strip()
    value = {"quantum expressions": "qex"}.get(value, value)
    if value not in BACKENDS:
        raise RuntimeError(f"Unknown backend: {name}")
    return value


def nim_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


# ──────────────────────────────────────────────────────────────────────
# A configured backend
# ──────────────────────────────────────────────────────────────────────

from build.config_model import BackendConfig
from build.grid_config import configure_grid
from build.qex_config import configure_qex
from build.quda_config import configure_quda


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
        lines.append(f"default.backend = {nim_string(default_backend)}")
    lines.append("format = 2")
    if nim:
        lines.append(f"nim = {nim_string(nim)}")
    for key in sorted(globals or {}):
        if (globals or {})[key]:
            lines.append(f"{key} = {nim_string((globals or {})[key])}")
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

import std/[os, strutils, json]

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
  let configText = readFile(quarkConf)
  let jsonValues = "format = 2" in configText.splitLines
  for raw in configText.splitLines:
    let line = raw.strip
    if line.len == 0 or line.startsWith("#"): continue
    if line.startsWith("[") and line.endsWith("]"):
      current = line[1 ..< line.high].strip
      continue
    if current != backend: continue
    let sep = line.find('=')
    if sep < 0: continue
    if line[0 ..< sep].strip == key:
      let value = line[sep + 1 .. line.high].strip
      result.add (if jsonValues: parseJson(value).getStr else: value)

proc setting(backend, key: string): string =
  ## Return one backend's value for `key` from quark.conf, or "".
  let values = settings(backend, key)
  if values.len > 0: values[^1] else: ""

proc quoted(flag: string): string =
  ## Quote a flag for the shell, since a flag may carry a list of C flags.
  quoteShell(flag)

proc canonicalBackend(name: string): string =
  case name.toLowerAscii.replace("_", " ").replace("-", " ").strip
  of "qex", "quantum expressions": "qex"
  of "grid": "grid"
  else: ""

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

  backend = canonicalBackend(backend)
  if backend.len == 0:
    echo "Select a supported Quark backend: grid or qex (QUDA is dependency-only)."
    quit(1)

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
  var command = quoted(nimExe) & " " & language
  command &= " " & quoted("--path:" & quarkRoot / "src")
  command &= " " & quoted("--nimcache:" & cacheDir / backend / name.splitFile.name)
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
    command &= " " & quoted(a)
  command &= " " & quoted("-d:quarkConfig=" & quarkConf)
  command &= " " & quoted("-o:" & binDir / name.splitFile.name)
  command &= " " & quoted(source)

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
FLAGS += "-d:backend=$(BACKEND)"
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
	@echo "  BACKEND=grid|qex         choose the backend (default: @DEFAULT_BACKEND@)"
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
.PHONY: $(BUILD_TARGETS)
$(BUILD_TARGETS):
	@$(NIM) build $(NIMS) $(FLAGS) $(ARGS) "$@"
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
            return f'  switch({nim_string(name)})'
        return f'  switch({nim_string(name)}, {nim_string(value)})'

    if not flag.startswith("-"):
        raise RuntimeError(f"Expected a Nim option, got {flag!r}")
    parts = re.split("[:=]", flag.lstrip("-"), maxsplit=1)
    name = {"d": "define", "u": "undef", "p": "path", "o": "out"}.get(parts[0], parts[0])
    return call(name, parts[1]) if len(parts) == 2 else call(name)


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

import std/strutils
const quarkBackend {.strdefine: "backend".} = "@DEFAULT_BACKEND@"
const quarkBackendNormalized = quarkBackend.toLowerAscii.replace("_", " ").replace("-", " ").strip
const quarkBackendCanonical = if quarkBackendNormalized == "quantum expressions": "qex" else: quarkBackendNormalized
when quarkBackendCanonical notin ["grid", "qex"]:
  {.error: "Select a supported Quark backend: grid or qex (QUDA is dependency-only).".}

'''


def write_quark_nims(path: Path, configs: list[BackendConfig],
                     default_backend: str, quark_conf: Path) -> None:
    """Write the Nim configuration a project outside this checkout includes."""
    lines = [QUARK_NIMS_HEADER
             .replace("@SELF@", str(path))
             .replace("@DEFAULT_BACKEND@", default_backend)]
    lines.append('switch("define", "backend=" & quarkBackendCanonical)')

    for cfg in configs:
        if not cfg.nimFlags:
            continue
        lines.append(f'when quarkBackendCanonical == "{cfg.name}":')
        lines.extend(_as_switch(flag) for flag in cfg.nimFlags)
        lines.append("")

    lines.append(_as_switch(f"-d:quarkConfig={quark_conf.resolve()}").lstrip())

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
        .replace('"@QUARK_ROOT@"', nim_string(str(quark_root.resolve())))
        .replace('"@BUILD_DIR@"', nim_string(str(build_dir.resolve())))
        .replace('"@NIM@"', nim_string(nim))
        .replace('"@QUARK_CONF@"', nim_string(str(quark_conf.resolve())))
        .replace("@DEFAULT_BACKEND@", default_backend))
    print(f"-- Wrote {nims}")

    makefile = build_dir / "Makefile"
    makefile.write_text(
        MAKEFILE
        .replace("@NIM@", shlex.quote(nim).replace("$", "$$").replace("#", "\\#"))
        .replace("@NIMS@", shlex.quote(str(nims)).replace("$", "$$").replace("#", "\\#"))
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
    user_nims.write_text(nims.read_text().replace(str(nims), str(user_nims))
                         .replace(nim_string("quarkConfig=" + str(source.resolve())),
                                  nim_string("quarkConfig=" + str(destination))))
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
    if args.nim:
        return str(Path(args.nim).resolve()) if os.sep in args.nim else args.nim
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

    wanted = {canonical_backend(name) for name in args.only} if args.only else None
    configs: list[BackendConfig] = []
    for name in BACKENDS:
        if name not in entries: continue
        if wanted is not None and name not in wanted: continue
        entry = entries[name]
        if not entry.get("prefix"):
            raise RuntimeError(f"The manifest names {name} but records no prefix")
        backend_prefix = Path(entry["prefix"]).resolve()
        try:
            cfg = CONFIGURERS[name](backend_prefix, entry, args)
            carry_provenance(cfg, entry)
            configs.append(cfg)
            print(f"-- Configured {name}: {backend_prefix}")
        except RuntimeError as exc:
            raise RuntimeError(f"Could not configure {name}:\n{exc}") from exc
    return configs


def choose_default(args: argparse.Namespace,
                   configs: list[BackendConfig]) -> str:
    """Return the backend an unqualified 'import quark' should use."""
    names = [c.name for c in configs if c.name != "quda"]
    if args.backend:
        chosen = canonical_backend(args.backend)
        if chosen == "quda":
            raise RuntimeError("QUDA is dependency-only; no conforming Quark adapter exists")
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
    output = Path(args.output).resolve() if args.output else build_dir / "quark.conf"

    if args.show:
        lines = ([f"default.backend = {nim_string(default_backend)}"] if default_backend else []) \
                + ["format = 2", f"nim = {nim_string(nim)}"] + [""] \
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
    write_quark_nims(nims, configs, default_backend, output)
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
