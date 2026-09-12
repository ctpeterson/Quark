# Milestone 1 closeout

Date: 2026-09-12

## Portable contracts

`tests/siteProvenance.nim` covers the distinction between statically incompatible Domain kinds and dynamically incompatible Geometry/Layout instances. `ScalarSite[L]` and `PackedSite[L]` retain their originating concrete Lattice; adapters reject differing kinds during compilation and call `conformable` before accessing same-kind Fields. Copies and Full selections retain their association. Equal extents, equal partition values, and even a shared Geometry with independently resolved Layout do not establish conformability. Default or fabricated indices cannot bypass the instance check. These rules use ordinary Nim types and values rather than introducing a distinct type for every runtime allocation.

`tests/executionScope.nim` checks explicit contexts for views, indexing, and parallel loops, lexical declaration visibility, copied and escaped view handles, nested placements, Site Proxy lifetime, and view cleanup on lexical exit and exception unwinding. Source-local unit tests in `base/execution.nim` observe exactly-once close actions and reverse close order, including return, break, failed acquisition, and exception unwinding. Both adapters use that same scope/owner protocol. Actual backend acquisition and synchronization remain Milestone 2 work; these checks establish the contract and close hook, not native storage acceptance.

Grid's local `local/grid/src/grid/Grid/lattice/Lattice_view.h` provides the reference model: `autoView` creates a view plus a `ViewCloser`, whose destructor calls `ViewClose`. Quark records the ownership choice in [ADR 0006](../adr/0006-bind-view-access-to-lexical-scopes.md).

Expansion inspection with `nim c --compileOnly --expandMacro:within --expandMacro:parallel` confirms an explicit placement constant, a fresh scope, and deferred cleanup. Generated C invokes view destruction and the scope close operation on its normal/exception cleanup path. Native QEX and Grid loop constructs remain scheduled for Milestone 2.

## Toolchain and source evidence

Following redirects with `curl --head --location --fail`, all four pinned toolchain URLs returned HTTP 200 on 2026-09-12:

| Toolchain | Architecture | Result |
| --- | --- | --- |
| Nim 2.2.8 | Linux x86-64 | HTTP 200 |
| Nim 2.2.8 | Linux AArch64 | HTTP 200 |
| LLVM 18.1.8 | Linux x86-64 | HTTP 200 |
| LLVM 18.1.8 | Linux AArch64 | HTTP 200 |

Exact URLs and expected SHA-256 hashes are in `build/archives.json`; checksum provenance is in `build/README.md`. Header checks establish that the archive locations resolve, not that all four payloads were downloaded again.

Recomputed SHA-256 hashes matched every cached archive under the existing `local/grid/src` and `local/qex/src` trees: ten files, comprising two Nim x86-64 archives and GMP, MPFR, FFTW, OpenSSL, HDF5, libunwind, QMP, and QIO. The bootstrap's `verify_archive` implementation performed the comparisons against the lock file. Both manifests already record these verified archive identities.

The recorded backend commits match their checkouts, and the recorded tracked patches, recursive submodule status, and untracked filenames also match:

| Backend | Commit |
| --- | --- |
| Grid | `7e702e5db0c8004a274d752bf79ff5aa26cc0b89` |
| QEX | `6d3464c14be2285438aa69eee2026c9077b087cc` |

`local/grid/bootstrap.json` and `local/qex/bootstrap.json` retain the source identities. Offline tests continue to check checksum failures, repository resolution, manifest recording, generated/installed configuration binding, settings round trips, and unsupported adapters.

## Verification result

At the original closeout, `nimble verify` passed with both QEX and Grid on the then-final module layout, including frozen-oracle checksums, the build fixtures, and the new scope/provenance tests. Lifetime tests also pass with `-d:release` for both adapters. Milestone 1 is complete; the next work is Milestone 2 Step 1 and its user-authored lifecycle oracle.

Milestone 1 cleanup also registers source-local execution, iteration, and backend Lattice/Numeric entry points in `nimble verify`. Backend implementation modules finish with unconditional conformance checks; source-local unit tests remain guarded by `when isMainModule`. The standards are recorded in `AGENTS.md`.

## Subsequent preparation

The [Milestone 1 to 2 handoff](milestone-1-to-2-handoff.md) records the expanded base unit suites, dependency and module cleanup, configuration-report consolidation, and the user-authorized Oracle A expansion. Its additional conformance gaps are current pre-integration work; the original closeout result above does not imply that the revised oracle passes.
