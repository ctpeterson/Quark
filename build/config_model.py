"""config model for the backend build contract."""

from __future__ import annotations

import shlex
import json

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

    def as_section(self) -> str:
        def value(text):
            return json.dumps(text, ensure_ascii=False)
        lines = [f"[{self.name}]", f"prefix   = {value(self.prefix)}"]
        if self.language:
            lines.append(f"language = {value(self.language)}")
        if self.passC:
            lines.append(f"passC    = {value(shlex.join(self.passC))}")
        if self.passL:
            lines.append(f"passL    = {value(shlex.join(self.passL))}")
        for flag in self.nimFlags:
            lines.append(f"nimFlag  = {value(flag)}")
        for key in sorted(self.extra):
            lines.append(f"{key} = {value(self.extra[key])}")
        return "\n".join(lines)
