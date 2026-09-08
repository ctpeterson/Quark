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
  # Every check names its backend. Backend selection is never implicit here:
  # one source compiled against each backend in turn is the property under
  # test, and a check that inherits a machine's configured default would
  # silently stop testing the other backend.
  exec "sha256sum --check oracle/oracles.sha256"
  for backend in ["qex", "grid"]:
    let select = " -d:backend=" & backend
    exec "nim check --path:src" & select & " src/quark.nim"
    exec "nim check --path:src" & select & " oracle/oracleA.nim"
    exec "nim r --path:src" & select & " tests/latticeInterface.nim"
    exec "nim r --path:src" & select & " tests/numericInterface.nim"

task config, "Show the build configuration this machine resolves":
  exec "nim r --hints:off --path:src src/quark/build/showConfig.nim"
