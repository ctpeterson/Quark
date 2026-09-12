# Portable acceptance programs

These files specify observable Quark behavior using the same source for every supported backend. The backend supplies its existing storage, layout construction and validation, arithmetic, iteration, lifecycle, and execution facilities. Quark adapters connect that machinery to the portable interface; these programs do not reimplement rank-partition validation or prescribe a backend's packing algorithm.

The September 12 expansion was requested by the user. All six sources are recorded in `oracles.sha256`; changing a recorded contract requires authorization and an accompanying entry in `docs/oracle-changes.md`. A frozen acceptance target may still be pending implementation. Passing a syntax check is not native acceptance.

| Oracle | Content | Milestone 2 acceptance |
| --- | --- | --- |
| A | Numeric Fields; mixed Integer/Real/Complex and S/D promotion; scalar/site operands; pointwise arithmetic; nonuniform data; partial updates; handle aliases, value copies, scope exits | Step 4 |
| B | Full/parity Lattices and Fields; repeated selections; same-domain positives; incompatible kinds and instances; parity iteration and arithmetic | Step 4; geometry prerequisites are covered by E in Step 2 |
| C | Vectors, square matrices, Spin, matrix-vector and noncommuting matrix products, nested spin-colour components, permissions and component lifetimes | Step 4 |
| D | One lifecycle per process, with normal, early-return, and exception exits | Step 1; run all three `oracleExit` variants |
| E | Backend-resolved geometry, Full and parity selection, provenance, unique Scalar/Packed iteration and coverage | Step 2 |
| F | Both execution contexts and both granularities, lexical nesting and missing-context rejection, independent of Field storage | Step 3; inspect native lowering |

Acceptance is cumulative: Step 1 requires D; Step 2 adds E; Step 3 adds F; Step 4 adds A, B, and C. Every step retains all earlier oracles for both QEX and Grid. `nimble verify` checks the freeze manifest and registers syntax checks; actual native builds and execution use the configured backend toolchains described in `INSTALL.md`.

## What to observe

D is compiled separately with `-d:oracleExit=normal`, `-d:oracleExit=return`, and `-d:oracleExit=raise`. Each process initializes/finalizes the backend once. Its ordinary Nim assertions check body and cleanup control flow. The backend integration harness must additionally trace the native initialization/finalization calls and establish that resource cleanup precedes finalization. A scaffold with no native lifecycle calls can pass those language-level assertions; it has not passed Step 1 acceptance.

E observes the geometry and sites exposed by the adapter, including parity selection. Its sets detect duplicate indices within one granularity and one Lattice; indices are not compared across granularities, parity kinds, ranks, or backend layouts. Counts are compared to exposed geometry, without implementing a rank-partition validator. The current one-site iterator scaffold cannot satisfy its runtime coverage assertions.

F deliberately avoids sharing ordinary host counters with accelerator loops or inventing a new buffer API merely for a test. Inspect generated source before native compiler dead-code elimination for the required Host and Accelerator loop constructs. Native backend probes establish execution-side iteration; A adds numerical coverage through nonuniform Field transformations once Fields exist. F's compile-time placement checks alone do not establish native lowering or runtime coverage.

A initializes a rank-local nonuniform pattern in a serial Scalar traversal, transforms it in parallel through Packed access, and observes it through a repeated Scalar traversal. Serial verification counters are never captured by a parallel kernel. The test relies on stable traversal of an unchanged Lattice, not a particular coordinate linearization or globally numbered sites. Partial ReadWrite updates then cross back through Accelerator Scalar execution. Whole-Field `:=` copies values; an ordinary handle assignment aliases storage.

A's mixed numeric cases assert both result classification and numerical values, including an S-precision Integer/Real intermediate that promotes to D only when combined with a D-precision Complex operand. Inputs such as `1.5` and `2-i` are exactly representable at Single precision. Double-precision observations use the stated `1e-12` absolute tolerance for these bounded examples. This does not define narrowing conversions, exceptional arithmetic, or a universal tolerance policy. Unsupported Half precision remains a backend capability decision rather than an unconditional rejection in these programs.

C preserves the user's `Vector[T, N]`, `Matrix[T, N]`, and `Spin[T]` spellings. Matrices are square; multiplication contracts components, and its literal test matrices do not commute. The same arithmetic templates exercise ordinary and Spin-tagged 3-component types, while nested 4-spin/3-colour Fields exercise canonical mathematical structure. Components retain mode, granularity, and lifetime. Numeric division at a leaf does not imply matrix division. Native physics-operator compatibility must additionally be checked at the adapter boundary; importing backend physics types into a portable oracle would defeat the seam.

## Current status and remaining scope

These are targets for the existing conformance scaffolds and subsequent native integration. A requires additional compound-update, real/integer observation and comparison, whole-Field-copy, and mixed-operand capabilities. B's native parity and Field operations remain pending. C requires concrete tensor families and tensor-aware Field operations. D/F can establish syntax and lexical control flow with scaffolding but still need the native evidence above. No oracle failure should be hidden by changing a result, mode, granularity, or placement.

Milestone 1 has been reopened to settle reductions and tensor/Field linear-algebra conformance before native integration. See the [interface proposals](../docs/notes/reduction-interface.md) and [backend research](../docs/research/grid-qex-reductions.md). These additions will receive new frozen acceptance programs once their syntax and semantics are accepted; the existing A–F sources remain unchanged.

Conflicting simultaneous Views, narrowing policy, Half-precision acceptance, exceptional arithmetic, shifts, halo exchange, and boundary conditions still need explicit portable contracts before their own acceptance programs are added. The present expansion does not invent those APIs or add duplicate backend algorithms.
