# Package
version       = "0.1.0"
author        = "Quark contributors"
description   = "A portable domain language for lattice field theory workloads"
license       = "MIT"
srcDir        = "src"

# Quark installs as an ordinary Nim package, so that any Nim file can
# `import quark` and any library can depend on it. The compiler and linker
# flags a backend needs travel with Quark's own source rather than with a
# build system: `src/quark/build/configuration.nim` finds this machine's
# configuration at compile time and `src/quark/backend/backend.nim` turns it
# into passC and passL pragmas. See INSTALL.md.
installDirs   = @["quark"]
installFiles  = @["quark.nim"]

requires "nim >= 2.2.8"

task verify, "Verify frozen oracles and the portable interface":
  # Every backend-dependent check names its backend explicitly:
  # one source compiled against each backend in turn is the property under
  # test, and a check that inherits a machine's configured default would
  # silently stop testing the other backend.
  exec "sha256sum --check oracle/oracles.sha256"
  exec "python3 -m unittest discover -s tests -p 'test_build.py'"
  exec "nim r --path:src tests/latticeConcept.nim"
  exec "nim r --path:src -d:latticeMissingSelection tests/latticeConcept.nim"
  exec "nim r --path:src -d:latticeWrongSelection tests/latticeConcept.nim"
  # Source-local unit tests run only when their owning module is the entry point.
  for module in ["lattice", "numeric", "tensor", "execution", "iteration", "field"]:
    exec "nim r --path:src src/quark/base/" & module & ".nim"
  for backend in ["qex", "grid"]:
    let select = " -d:backend=" & backend
    for module in ["Lattice", "Numeric"]:
      exec "nim r --path:src" & select & " src/quark/backend/" & backend &
        "/" & backend & module & ".nim"
    exec "nim check --path:src" & select & " src/quark.nim"
    for oracle in ["A", "B", "C", "D", "E", "F"]:
      exec "nim check --path:src" & select & " oracle/oracle" & oracle & ".nim"
    for exitPath in ["return", "raise"]:
      exec "nim check --path:src" & select & " -d:oracleExit=" & exitPath & " oracle/oracleD.nim"
    exec "nim r --path:src" & select & " tests/latticeInterface.nim"
    exec "nim r --path:src" & select & " tests/latticeConformability.nim"
    exec "nim r --path:src" & select & " tests/numericInterface.nim"
    exec "nim check --path:src" & select & " tests/tensorConcept.nim"
    exec "nim check --path:src" & select & " tests/fieldConcept.nim"
    exec "nim check --path:src" & select & " tests/fieldTensorConcept.nim"
    exec "nim r --path:src" & select & " tests/fieldInterface.nim"
    exec "nim r --path:src" & select & " tests/fieldSyntax.nim"
    exec "nim r --path:src" & select & " tests/siteProvenance.nim"
    exec "nim r --path:src" & select & " tests/executionScope.nim"

task config, "Show the build configuration this machine resolves":
  exec "nim r --hints:off --path:src src/quark/build/configuration.nim"
