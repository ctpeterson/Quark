# Quark roadmap

## Oracle A endpoint

`oracle/oracleA.nim` is complete when its frozen source:

- compiles and passes unchanged with both the QEX and Grid adapters;
- uses no backend-selection branches or backend-owned types;
- preserves typed Scalar Site and Packed Site access with Lattice provenance;
- makes every execution placement and site-granularity choice explicit;
- enforces the declared Field View access modes;
- maps QEX Field Views to the corresponding host or accelerator access mechanisms;
- lowers QEX Host Parallel Site Loops through `threads` regions with ordinary Nim loops and QEX Accelerator Parallel Site Loops through QEX's native accelerator iteration mechanism;
- lowers Grid Accelerator Parallel Site Loops through `accelerator_for` and Grid Host Parallel Site Loops through `thread_for`;
- maps Grid Field Views to the corresponding host or accelerator access modes;
- produces deterministic, inspectable lowering; and
- passes focused positive, negative, and numerical checks.

A Grid/QEX GPU run is valuable evidence when suitable hardware is available. Oracle A completion requires the accelerator lowering to be generated and inspected, but does not depend on access to a particular GPU machine.

## Frozen follow-on: Oracle B

`oracle/oracleB.nim` freezes the follow-on contract for Lattice Decompositions and Field Domains. A Lattice produces a first-class Decomposition whose immutable Domains carry Lattice and Decomposition provenance; Fields and iteration spaces constructed from a Domain preserve that identity, while the Full Decomposition remains equivalent to direct Lattice construction.

Oracle B remains outside the active Oracle A milestones. Its implementation begins only after the current objective is complete or the roadmap is explicitly reordered.

## Milestone 0 — Contract and frozen oracle

Status: complete.

Completion criteria:

- Quark's thesis and governing invariants are recorded in `AGENTS.md`.
- `CONTEXT.md` defines the vocabulary exercised by Oracle A.
- the Nim toolchain decision is accepted in ADR 0001;
- `oracle/oracleA.nim` uses only the accepted access modes; and
- its checksum is recorded in `oracle/oracles.sha256` and verified by `nimble verify`.

## Milestone 1 — Portable interface and backend seam

Define the smallest Quark interface required by Oracle A: Lattice, Field, Field View, access modes, explicit Execution Contexts, Site Granularities, iteration spaces, Site Indices, `:=`, and `parallel for`. Define one compile-time backend-selection seam with QEX and Grid adapters; keep backend types out of Oracle A.

Progress: `Geometry`, `Partition`, and `Lattice` are structural interfaces exercised by temporary QEX and Grid conformance scaffolds. Lattice directly exposes the Rank Partition and resulting Rank Geometry followed by the Packed Partition and resulting Packed Geometry; Layout remains the domain name for that resolution and its backend linearization rather than a separate portable concept. `IntegerNumber`, `RealNumber`, and `ComplexNumber` classify adapter-owned numeric families by portable Precision and Numeric Kind while `IntegerArithmetic`, `RealArithmetic`, and `ComplexArithmetic` require semantically closed same-Kind arithmetic. Mixed arithmetic follows Quark's portable Numeric Promotion rules, while the selected adapter supplies the concrete `Integer[P]`, `Real[P]`, and `Complex[P]` types required in Field type arguments. The scaffolds validate a regular, exactly divisible partition chain and the numeric interface, but must be replaced or reshaped around native backend types in their vertical slices.

The bootstrap, configuration, and generated-build workflow is an experimental implementation of the backend build-integration seam. ADR 0004 makes its hardening part of Milestone 1: shared orchestration must delegate backend knowledge, generated builds must use exactly their selected configuration, external settings must round-trip without loss, inputs and provenance must be reproducible, and only conforming adapters may be selected as Quark backends.

Completion criteria:

- every Oracle A construct resolves through `import quark`;
- backend selection occurs outside Oracle A;
- focused compile-time tests reject cross-lattice indexing and illegal Field View access;
- Scalar Site and Packed Site accesses have distinct result types;
- every placement-sensitive Oracle A construct belongs to an explicit Execution Context;
- skeletal QEX and Grid adapters satisfy the same portable interface without conditional branches in Oracle A;
- generated and installed builds bind to one explicit configuration, including custom build directories and canonical backend aliases;
- fixture-based build tests cover configuration extraction, QEX list-valued settings, paths requiring shell quoting, generated files, and unsupported backends;
- supported toolchain downloads resolve, downloaded artifacts are verified, and backend source revisions are recorded precisely enough to reproduce and inspect a build; and
- direct backend selection rejects QUDA until a QUDA adapter satisfies the portable interface.

## Milestone 2 — QEX vertical slice

Implement Oracle A through the QEX adapter. Identify QEX's native accelerator iteration and view mechanisms before fixing the lowering; Quark still checks Field View scope and access modes.

Completion criteria:

- the frozen Oracle A compiles and all assertions pass with QEX;
- Host Parallel Site Loops lower through QEX `threads` regions containing ordinary Nim loops;
- Accelerator Parallel Site Loops lower through QEX's documented native accelerator iteration mechanism, without silently becoming Host Execution Context loops;
- Field View access modes select the corresponding QEX host or accelerator mechanisms and close at scope exit;
- Scalar Site and Packed Site iteration use the intended QEX iteration spaces;
- directions and sequences of Fields behave as Oracle A specifies; and
- expanded/generated Nim is inspected by a focused lowering test.

## Milestone 3 — Grid vertical slice

Implement the same portable interface through the Grid adapter, reusing Grim where it remains a faithful adapter and deepening or replacing it where Quark semantics require a different interface.

Completion criteria:

- the same frozen Oracle A compiles and all assertions pass with Grid on a CPU build;
- Accelerator Parallel Site Loops lower to `accelerator_for`;
- Host Parallel Site Loops lower to `thread_for`;
- Field View access modes select the correct Grid host or accelerator modes and close at scope exit;
- Scalar Site and Packed Site accesses preserve their distinct value types; and
- generated C++ is inspected by focused lowering tests.

## Milestone 4 — Oracle A acceptance

Harden the completed slice as the first durable proof of Quark's thesis.

Completion criteria:

- the QEX and Grid acceptance matrix runs from one project command;
- focused negative tests cover every enforceable governing invariant exercised by Oracle A;
- numerical results agree across adapters;
- generated-code checks pin the required parallel-loop and view constructs without pinning irrelevant formatting;
- setup and failure diagnostics identify the selected backend and missing capabilities clearly; and
- all project checks, oracle checksums, and repository hygiene checks pass.
