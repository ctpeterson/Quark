# Package
version       = "0.1.0"
author        = "Quark contributors"
description   = "An experimental Nim project for lattice field theory"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.2.8"

task verify, "Verify frozen oracles and compile-check the library":
  exec "sha256sum --check oracle/oracles.sha256"
  exec "nim check --path:src src/quark.nim"
