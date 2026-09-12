"""Pinned upstream archives. See build/README.md for checksum provenance."""

import hashlib
import json
from pathlib import Path


class IntegrityError(RuntimeError):
    """An archive is untrusted; do not turn this into a dependency fallback."""


def archive_spec(url: str) -> dict:
    entries = json.loads(Path(__file__).with_name("archives.json").read_text())
    if url not in entries:
        raise IntegrityError(f"No pinned SHA-256 for {url}; add a reviewed archive entry")
    return entries[url]


def verify_archive(path: Path, expected: str) -> None:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise IntegrityError(f"SHA-256 mismatch for {path}: expected {expected}, got {digest.hexdigest()}")


def toolchain_archive(tool: str, version: str, arch: str) -> str:
    if tool == "nim":
        url = f"https://nim-lang.org/download/nim-{version}-linux_{arch}.tar.xz"
    elif tool == "llvm" and version == "18.1.8":
        suffix = {"x64": "x86_64-linux-gnu-ubuntu-18.04",
                  "arm64": "aarch64-linux-gnu"}[arch]
        url = (f"https://github.com/llvm/llvm-project/releases/download/llvmorg-{version}/"
               f"clang+llvm-{version}-{suffix}.tar.xz")
    else:
        raise IntegrityError(f"No supported {tool} archive for {version}/{arch}")
    archive_spec(url)
    return url
