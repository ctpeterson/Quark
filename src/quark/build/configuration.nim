#[
Configuration

src: quark/build/configuration.nim
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

Quark is an ordinary Nim package. Installing it with Nimble and writing
`import quark` in any Nim file must work, and a library must be able to depend
on Quark without carrying a build system of its own. That is only possible if
the compiler flags a backend needs travel with Quark's own source rather than
with a Makefile, so this module finds the machine's Quark configuration at
compile time and `backend.nim` turns it into `passC` and `passL` pragmas.

The configuration is written by `./configure`, which reads back how each
backend was actually built (Grid's `grid-config`, QEX's `qexconfig.nims`,
QUDA's CMake cache) rather than deriving any of it a second time.

Search order, first hit wins:

1. `-d:quarkConfig=PATH`, an explicit path
2. `$QUARK_CONFIG`, an explicit path in the environment
3. `<quark source root>/local/quark.conf`, the configuration belonging to a
   source checkout, which makes a development build work with no setup
4. `~/.config/quark/config`, the per-user configuration an installed Quark uses

An absent configuration is not an error. Quark's portable interface compiles
without one, and only a backend that needs flags to link reports the omission.

File format
-----------
    # comment
    default.backend = grid

    [grid]
    prefix   = /home/me/quark/local/grid
    language = cpp
    passC    = -I/home/me/quark/local/grid/include
    passL    = -L/home/me/quark/local/grid/lib -lGrid

Keys before any section header are global. Later keys of the same name in a
section replace earlier ones.

Generated files declare `format = 2` and encode every other value as a JSON
string, preserving whitespace and escapes. The unquoted legacy form above
remains supported when no format marker is present.

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
]#

import std/[macros]
import std/[os]
import std/[strutils]
import std/[json]

const
  quarkConfigOverride* {.strdefine: "quarkConfig".} = ""
    ## Explicit configuration path, set with `-d:quarkConfig=PATH`.

  quarkConfigEnvVar* = "QUARK_CONFIG"
    ## Environment variable holding an explicit configuration path.

  quarkUserConfig* = ".config" / "quark" / "config"
    ## Per-user configuration, relative to the home directory.

  quarkCheckoutConfig* = "local" / "quark.conf"
    ## Configuration belonging to a source checkout, relative to its root.

proc sourceRoot: string {.compileTime.} =
  ## Return the root of the Quark source tree holding this file.
  ##
  ## `currentSourcePath` gives `<root>/src/quark/build/configuration.nim`, so
  ## the root is four directories up. This is what lets a checkout find its own
  ## configuration without the environment being set up first.
  currentSourcePath().parentDir.parentDir.parentDir.parentDir

proc findConfig: string {.compileTime.} =
  ## Return the path of the configuration to use, or the empty string.
  if quarkConfigOverride.len > 0: return quarkConfigOverride
  let fromEnv = getEnv(quarkConfigEnvVar)
  if fromEnv.len > 0: return fromEnv
  let checkout = sourceRoot() / quarkCheckoutConfig
  if fileExists(checkout): return sourceRoot() / quarkCheckoutConfig
  let user = getHomeDir() / quarkUserConfig
  if fileExists(user): return user
  return ""

const
  quarkConfigPath* = findConfig()
    ## Path of the configuration in use, empty when none was found.

  quarkConfigured* = quarkConfigPath.len > 0 and fileExists(quarkConfigPath)
    ## Whether a Quark configuration was found.

  configText = when quarkConfigured: staticRead(quarkConfigPath) else: ""
  jsonValues = "format = 2" in configText.splitLines

when quarkConfigPath.len > 0 and not quarkConfigured:
  {.error: "Quark configuration does not exist: " & quarkConfigPath.}

proc lookup(section, key: string): string {.compileTime.} =
  ## Return the value of `key` within `section`, or the empty string.
  ##
  ## A `section` of `""` names the keys appearing before any section header.
  var current = ""
  for rawLine in configText.splitLines:
    let line = rawLine.strip
    if line.len == 0 or line.startsWith("#"): continue
    if line.startsWith("[") and line.endsWith("]"):
      current = line[1 ..< line.high].strip
      continue
    if current != section: continue
    let separator = line.find('=')
    if separator < 0: continue
    if line[0 ..< separator].strip == key:
      let value = line[separator + 1 .. line.high].strip
      result = if jsonValues and key != "format": parseJson(value).getStr else: value

proc quarkSetting*(backend, key: string): string {.compileTime.} =
  ## Return one backend's configured value for `key`, or the empty string.
  lookup(backend, key)

proc quarkValues*(section, key: string): seq[string] {.compileTime.} =
  ## Return every value `key` has in `section`.
  ##
  ## A key may appear more than once: `nimFlag` does, one flag per line,
  ## because a compiler flag list contains spaces and so could not be
  ## recovered from a single whitespace-joined field.
  var current = ""
  for rawLine in configText.splitLines:
    let line = rawLine.strip
    if line.len == 0 or line.startsWith("#"): continue
    if line.startsWith("[") and line.endsWith("]"):
      current = line[1 ..< line.high].strip
      continue
    if current != section: continue
    let separator = line.find('=')
    if separator < 0: continue
    if line[0 ..< separator].strip == key:
      let value = line[separator + 1 .. line.high].strip
      result.add (if jsonValues and key != "format": parseJson(value).getStr else: value)

proc quarkGlobalSetting*(key: string): string {.compileTime.} =
  ## Return one configuration-wide value, or the empty string.
  lookup("", key)

proc quarkCanonicalBackend*(name: string): string {.compileTime.} =
  ## Return the canonical name of a backend selector, or the empty string.
  ##
  ## Backend names reach Quark from two directions that must agree: the
  ## `--backend` given to `./bootstrap`, and the `-d:backend=` given to the
  ## compiler. Both accept the spellings below so that one name serves for the
  ## whole workflow. Nim identifier normalisation does not apply to string
  ## defines, so the spellings are matched here instead.
  return case name.toLowerAscii.replace("_", " ").replace("-", " ").strip:
    of "qex", "quantum expressions": "qex"
    of "grid": "grid"
    of "quda": "quda"
    else: ""

proc quarkConfiguredBackends*(): seq[string] {.compileTime.} =
  ## Return the backends this machine has a configuration for.
  for candidate in ["grid", "qex", "quda"]:
    if quarkSetting(candidate, "prefix").len > 0:
      result.add candidate

const
  quarkDefaultBackend* =
    block:
      # A configured machine names the backend `import quark` should use when
      # the compiler was given no `-d:backend=`. Without a configuration there
      # is nothing to default to, and the choice stays explicit.
      let named = quarkCanonicalBackend(quarkGlobalSetting("default.backend"))
      if named.len > 0: named
      else:
        let available = quarkConfiguredBackends()
        if available.len == 1: available[0] else: ""

proc quarkSections*(): seq[string] {.compileTime.} =
  ## Return every section name in the configuration, in the order written.
  for rawLine in configText.splitLines:
    let line = rawLine.strip
    if line.startsWith("[") and line.endsWith("]"):
      let name = line[1 ..< line.high].strip
      if name.len > 0 and name notin result:
        result.add name

proc quarkKeys*(section: string): seq[string] {.compileTime.} =
  ## Return the keys defined in one section, in the order written.
  ##
  ## Reported generically rather than from a fixed list, so that a fact
  ## `configure` learns to record shows up in the compile-time report without
  ## this module being taught about it.
  var current = ""
  for rawLine in configText.splitLines:
    let line = rawLine.strip
    if line.len == 0 or line.startsWith("#"): continue
    if line.startsWith("[") and line.endsWith("]"):
      current = line[1 ..< line.high].strip
      continue
    if current != section: continue
    let separator = line.find('=')
    if separator < 0: continue
    let key = line[0 ..< separator].strip
    if key.len > 0 and key notin result:
      result.add key

proc quarkReportLines*(backend = ""): seq[string] {.compileTime.} =
  ## Return a human-readable account of what Quark is building against.
  ##
  ## This is the provenance of a binary: which configuration was found, which
  ## backend was selected, and every setting `configure` read back from how
  ## that backend was actually built.
  proc row(label, value: string, width: int, indent = 2): string =
    " ".repeat(indent) & label.alignLeft(width) & "  " & value

  proc width(labels: seq[string], least: int): int =
    result = least
    for label in labels: result = max(result, label.len)

  result.add "Quark build configuration"
  if not quarkConfigured:
    result.add "  config  none found"
    result.add ""
    result.add "  Quark's portable interface compiles without one, but a"
    result.add "  backend needs one to link. Run ./configure to write it."
    return

  # The configuration as a whole: where it came from and what it offers.
  let available = quarkConfiguredBackends()
  let globalKeys = quarkKeys("")
  let globalWidth = width(globalKeys & @["config", "available"], 0)
  result.add row("config", quarkConfigPath, globalWidth)
  for key in globalKeys:
    result.add row(key, quarkGlobalSetting(key), globalWidth)
  result.add row("available",
                 if available.len > 0: available.join(", ") else: "none",
                 globalWidth)

  let selected = if backend.len > 0: backend else: quarkDefaultBackend
  if selected.len == 0:
    result.add ""
    result.add "  No backend selected; pass -d:backend=NAME."
    return

  # The selected backend, and everything known about how it was built.
  result.add ""
  result.add row("backend", selected, globalWidth)
  if quarkSetting(selected, "prefix").len == 0:
    result.add "  " & selected &
      " is not configured here; building without its flags."
    return
  let keys = quarkKeys(selected)
  let keyWidth = width(keys, 0)
  for key in keys:
    let values = quarkValues(selected, key)
    if values.len <= 1:
      result.add row(key, quarkSetting(selected, key), keyWidth, indent = 4)
    else:
      # A repeated key is one setting per line rather than one crowded line.
      for i, value in values:
        result.add row(if i == 0: key else: "", value, keyWidth, indent = 4)

proc quarkReport*(backend = "") {.compileTime.} =
  ## Echo the build configuration during compilation.
  for line in quarkReportLines(backend):
    echo line

macro quarkBackendFlags*(name: static string): untyped =
  ## Emit the compiler and linker flags one backend was configured with.
  ##
  ## This is what makes Quark installable. A downstream project compiles
  ## against Quark's own source, so emitting the flags here means that project
  ## needs no build system of its own to link a backend correctly.
  ##
  ## A macro rather than a template so that a backend with no configured
  ## flags emits no pragma at all, and a backend with them emits the flags as
  ## a literal, where they stay readable in the generated compile command.
  result = newStmtList()
  for pragma in ["passC", "passL"]:
    let flags = quarkSetting(name, pragma)
    if flags.len > 0:
      result.add nnkPragma.newTree(
        nnkExprColonExpr.newTree(ident(pragma), newLit(flags)))

when isMainModule:
  # Resolve the report at compile time, just as an importing program does.
  const report = quarkReportLines()
  for line in report:
    echo line
