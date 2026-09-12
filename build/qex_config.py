"""qex config for the backend build contract."""

from __future__ import annotations

import argparse
from pathlib import Path

from build.config_model import BackendConfig

import ast
import io
import tokenize
import os

def read_qexconfig(path: Path) -> dict:
    """Read QEX's literal assignments, references, and concatenations.

    Reject expressions outside this subset instead of silently losing native
    compiler settings. Quoted comment markers and ampersands remain data.
    """
    settings: dict = {}

    def evaluate(node):
        if isinstance(node, ast.Constant) and type(node.value) in (str, int):
            return str(node.value)
        if isinstance(node, ast.Name) and node.id in settings:
            return settings[node.id]
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and not node.args and not node.keywords:
            if node.func.id == "getCurrentDir":
                return str(path.resolve().parent)
            if node.func.id == "getHomeDir":
                return str(Path.home()) + os.sep
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
            return str(Path(evaluate(node.left)) / evaluate(node.right))
        if isinstance(node, ast.List):
            values = [evaluate(item) for item in node.elts]
            if all(isinstance(item, str) for item in values):
                return values
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitAnd):
            left, right = evaluate(node.left), evaluate(node.right)
            if type(left) is type(right):
                return left + right
        raise ValueError("unsupported QEX expression")

    # Tokenization protects string contents when translating Nim's @[].
    tokens = tokenize.generate_tokens(io.StringIO(path.read_text()).readline)
    translated = tokenize.untokenize(
        token for token in tokens if token.string != "@" or
        token.type != tokenize.OP)
    for number, raw in enumerate(translated.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, expression = line.partition("=")
        key = key.strip()
        if not key.isidentifier():
            continue
        try:
            settings[key] = evaluate(ast.parse(expression.strip(), mode="eval").body)
        except (SyntaxError, ValueError, TypeError) as exc:
            raise RuntimeError(f"{path}:{number}: cannot resolve QEX setting {key}") from exc
    return settings


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

    cfg.language = settings.get("ccDef", "cc")
    if cfg.language not in ("cc", "cpp"):
        raise RuntimeError(f"Unsupported QEX language: {cfg.language}")
    for key, value in settings.items():
        if key not in ("envs", "nimargs") and not isinstance(value, str):
            raise RuntimeError(f"QEX {key} must be a scalar setting")

    # QEX's source has to be on Nim's search path, since Quark's QEX adapter
    # compiles against QEX's own modules rather than a compiled library.
    source = Path(entry.get("source") or (prefix / "qex"))
    qex_src = source / "src"
    if qex_src.exists():
        cfg.nimFlags.append(f"--path:{qex_src}")
    else:
        raise RuntimeError(f"QEX source directory does not exist: {qex_src}")

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
        if key in settings:
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
        elif instruction_set:
            raise RuntimeError(f"Unsupported QEX SIMD setting: {instruction_set}")
    vlen = settings.get("vlen", "")
    if vlen:
        cfg.nimFlags.append(f"--putenv:VLEN={vlen}")
        cfg.note("vlen", vlen)

    # Environment variables and extra Nim arguments QEX bakes into a build,
    # including the '-d:Backend=...' that selects its accelerator.
    for value in sequence_setting(settings, "envs"):
        cfg.nimFlags.append(f"--putenv:{value}")
    for value in sequence_setting(settings, "nimargs"):
        cfg.nimFlags.append(value)

    cfg.note("config", str(config))
    cfg.note("source", str(source))
    cfg.note("simd", simd)
    cfg.note("accelerator", entry.get("accelerator", ""))
    return cfg


def sequence_setting(settings: dict, key: str) -> list[str]:
    value = settings.get(key, [])
    if not isinstance(value, list):
        raise RuntimeError(f"QEX {key} must be a sequence of strings")
    return value
