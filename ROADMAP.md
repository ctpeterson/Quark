# Quark roadmap

Zero abstraction overhead is a project-wide design and acceptance constraint. [ADR 0011](docs/adr/0011-require-zero-abstraction-overhead.md) requires parity with an equivalent direct-backend program's runtime work and storage while preserving the same semantics. Milestone 1 establishes interfaces and comparison criteria; every native capability accepted in Milestone 2 must demonstrate this property, and Milestone 3 retains the regression evidence.

## Oracle-driven progress

User-authored oracles define the capabilities and acceptance criteria for implementation. Oracle A establishes an initial integrated program; further oracles guide the successive layers of Milestone 2. Each accepted oracle is frozen before its implementation work and assigned to the step whose behavior it specifies.

Acceptance is cumulative: completing a step requires its assigned oracles and every oracle accepted at earlier steps to pass unchanged against both QEX and Grid, with the required numerical, rejection, and generated-code evidence. Retain those checks throughout later work. Future-step oracles can remain pending until their assigned step; record that assignment and status explicitly. Focused implementation tests supplement the oracles.

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

`oracle/oracleB.nim` freezes the follow-on contract for a directly constructed Full Lattice and parity Lattices derived through `newSublattice(EvenParity)` and `newSublattice(OddParity)`. Fields and iteration spaces preserve their Lattice's immutable selection and source association. ADR 0003 records why Decomposition and Domain no longer require separate public objects or concepts.

The Lattice selection and conformability seam is brought forward into Milestone 1. This initial slice checks conditional Full construction, shared-instance conformability in both adapters, and distinct-kind selection and comparisons in type-contract fixtures. Adapter integration with backend parity facilities, Field and Site Index enforcement, and Oracle B acceptance remain follow-on work.

## Preparation between Milestones 1 and 2

The user-authorized September 12 oracle expansion covers numeric promotion and Field behavior in A, parity Fields in B, tensor Fields in C, and early-step contracts in D–F. The [oracle acceptance matrix](oracle/README.md) assigns D to Step 1, E to Step 2, F to Step 3, and A/B/C to Step 4, with cumulative acceptance. See the [handoff record](docs/notes/milestone-1-to-2-handoff.md) for completed cleanup, verification evidence, and proposed further oracles. Oracle A remains the integrated Step 4 endpoint; its new syntax/conformance requirements must be addressed before starting native integration. The original Milestone 1 closeout remains historical evidence for the earlier contract.

Before native integration:

- complete scalar/Complex `+=` and the `-=`, `*=`, `/=` operand-pair and permission checks in both adapters' conformance scaffolds;
- support the Host Scalar real absolute-value and comparison operations required by Oracle A's numerical checks;
- restore a green `nimble verify` with the expanded frozen Oracle A; and
- complete the additional mixed-numeric, copy/provenance, and tensor operand-pair conformance exposed by A–C.

The early-step sources are now defined: D exercises one lifecycle per process, E includes native Full/parity geometry and iteration, and F establishes execution intent. Oracle B's geometry prerequisites therefore belong to Step 2; its complete Field acceptance belongs to Step 4. Backends supply existing native operations and validation; the portable layer does not duplicate rank-partition validation.

The source cleanup is complete: 192 independent base-module unit tests, the base/backend import boundary, `backend/common/commonField.nim`, and configuration reporting directly from `build/configuration.nim`. Oracle C is now a frozen tensor acceptance target, and all six base modules have detailed module-level documentation.

## Milestone 0 — Contract and frozen oracle

Status: complete.

Completion criteria:

- Quark's thesis and governing invariants are recorded in `AGENTS.md`.
- `CONTEXT.md` defines the vocabulary exercised by Oracle A.
- the Nim toolchain decision is accepted in ADR 0001;
- `oracle/oracleA.nim` uses only the accepted access modes; and
- its checksum is recorded in `oracle/oracles.sha256` and verified by `nimble verify`.

## Milestone 1 — Portable interface and backend seam

Status: active, reopened (2026-09-12) for lattice reductions and tensor/Field linear-algebra contracts. The earlier [closeout evidence](docs/notes/milestone-1-closeout.md) applies to the interface before these additions.

Define the smallest Quark interface required by Oracle A: Lattice, Field, Field View, access modes, explicit Execution Contexts, Site Granularities, iteration spaces, Site Indices, `:=`, and `parallel for`. Define one compile-time backend-selection seam with QEX and Grid adapters; keep backend types out of Oracle A.

Reopened scope: settle useful lattice-reduction syntax inside an explicit Execution Context, informed by QEX and Grid's existing reduction facilities. Add tensor and Field conformance for trace, determinant, squared norms, infinity norms, Hermitian outer products (`v * w†`), and vector inner products (`v†w`). Tensor-valued Field contractions produce Numeric-valued Fields on the same Lattice; reducing across lattice sites is a separate operation. The compound numeric classification is now `Numeric[P]`; the individual `IntegerNumber`, `RealNumber`, and `ComplexNumber` classifications retain their names. See the [reduction research](docs/research/grid-qex-reductions.md) and [interface proposals](docs/notes/reduction-interface.md) for backend evidence and decisions still to settle.

Scope: Milestone 1 establishes portable syntax, type and semantic contracts, adapter conformance, and the build contracts listed below. QEX and Grid provide storage, memory access, and execution machinery. Milestone 2 connects Quark's operations to those existing backend facilities in parallel across both adapters and verifies the resulting execution and generated code. Milestone 1 does not require that integration, backend compilation, or a native execution probe. Judge and report its progress against its own completion criteria; deferred backend integration is not a Milestone 1 defect or prerequisite for further interface work.

Progress: `Geometry`, `Partition`, and `Lattice` are structural interfaces exercised by temporary QEX and Grid conformance scaffolds. Lattice directly exposes the Rank Partition and resulting Rank Geometry followed by the Packed Partition and resulting Packed Geometry; Layout remains the domain name for that resolution and its backend linearization rather than a separate portable concept. `IntegerNumber`, `RealNumber`, and `ComplexNumber` classify adapter-owned numeric families by portable Precision and Numeric Kind while `IntegerArithmetic`, `RealArithmetic`, and `ComplexArithmetic` require semantically closed same-Kind arithmetic. Mixed arithmetic follows Quark's portable Numeric Promotion rules, while the selected adapter supplies the concrete `Integer[P]`, `Real[P]`, and `Complex[P]` types required in Field type arguments. The scaffolds validate a regular, exactly divisible partition chain and the numeric interface for this milestone.

The bootstrap, configuration, and generated-build workflow is an experimental implementation of the backend build-integration seam. ADR 0004 makes its hardening part of Milestone 1: shared orchestration must delegate backend knowledge, generated builds must use exactly their selected configuration, external settings must round-trip without loss, inputs and provenance must be reproducible, and only conforming adapters may be selected as Quark backends.

Build integration progress: backend-owned configuration readers, explicit generated/installed configuration binding, canonical selectors, lossless JSON string values, and direct QUDA rejection are covered by offline fixtures. Bootstrap pins archive checksums, resolves source revisions to recorded commits, and records patches and dependency/toolchain fallback identities. The completion criteria below determine the remaining portable-interface and build-contract work.

Lattice seam progress: the merged concept checks same-type `conformable` and requires direct construction and parity selection only for Full, including the result's Lattice conformance and requested kind. Both adapters expose a static kind, independent kind parameters for comparisons, and identity-preserving Full selection. Focused fixtures verify distinct derived types, cross-kind comparison, and rejection of missing constructors, missing selectors, wrong selection kinds, and missing cross-type operations. The adapters expose typed parity selectors but raise an explicit unsupported-operation error until the adapters connect to backend parity facilities; fixture conformance is not Oracle B acceptance.

Field seam progress: `FieldObject[T]` classifies site type, Lattice association, and mode-correct views independently of constructor conformance. QEX and Grid expose concrete shared Field handles and `newField(T)` constructors. Focused tests check constructor result types, retained Lattice instances, handle aliasing, sequence storage, and malformed view/proxy metadata. QEX and Grid supply concrete `FieldView[T, Mode, LatticeType]` families satisfying `FieldViewObject[T]`, with the Lattice type defaulting to Full for explicit annotations. Inferred views preserve static access modes and distinct site index types; focused tests reject mismatched mode annotations and runtime mode arguments. Field classification and constructor conformance are complete for this Milestone 1 slice. Scope ownership, explicit contexts, and Site Index provenance are now enforced by the adapter scaffolds and covered by focused checks.

Field scope: `base/field.nim` contains access modes and the Field, View, and Site Proxy classification contracts. Whole-Field expression representation and evaluation machinery remain deferred; the newly required pointwise linear-algebra result contracts belong to the reopened Milestone 1. The adapters retain shared internal placeholders for Oracle A syntax; unimplemented Field operations explicitly raise unsupported-operation errors at runtime. The current Field checks validate syntax, type conformance, and access-mode rejection. Numeric Site Proxy conformance now requires the site type's Integer, Real, or Complex arithmetic for readable modes; focused checks cover result kind, precision, chained operations, and Scalar/Packed granularity. Vector and square-matrix structure/arithmetic contracts and Spin-tag classification now have independent conformance fixtures, including recursive components and spin preservation. Ordinary tensors require no index-space metadata; `SpinObject` recognizes spin types through a compile-time `isSpin = true` query. Field Site Proxy conformance now selects those tensor capabilities and recursively checks component access modes and Scalar/Packed index types, including WriteDiscard component handles. Resolving tensor type arguments as mathematical descriptions or value families, and operand-pair conformance, remain Milestone 1 preparation; native tensor and Field behavior belong to Milestone 2 acceptance.

Earlier closeout (before the oracle expansion): `within` owns a lexical scope with exactly-once view cleanup, including exception unwinding; copied views and Site Proxies cannot extend access lifetime. Views, indexed access, and Parallel Site Loops require an explicit context. Scalar and Packed indices retain their Lattice, with compile-time rejection of incompatible Domain kinds and runtime rejection of incompatible Geometry/Layout instances. All four supported toolchain archive URLs resolve, ten cached archives match their pins, and both backend manifests match their source identities. `nimble verify` passed for both adapters at that closeout, as did release-mode lifetime tests. The expanded Oracle A currently exposes additional conformance gaps; that historical green result does not complete the reopened milestone.

Cleanup: source-local unit tests run under `when isMainModule` as part of `nimble verify`; backend implementation modules finish with unconditional static conformance checks. All six base modules contain expanded self-contained unit suites with independent fixtures and no backend imports; `nimble verify` runs them without backend selection. Field integration and cross-module rejection fixtures remain under `tests/`. Shared Field scaffolding lives in `backend/common/commonField.nim`.

Completion criteria:

- every Oracle A construct resolves through `import quark`;
- the expanded A–C syntax and operand-pair contracts pass conformance checks for both adapters, including resolution of tensor type arguments in Field declarations;
- implement the accepted separation of mathematical tensor descriptions from native storage/access/results ([ADR 0009](docs/adr/0009-separate-tensor-descriptions-from-native-values.md)) and the static-kind Site family ([ADR 0010](docs/adr/0010-parameterize-site-kind-statically.md)), preserving the frozen oracles and their conformance guarantees;
- each interface has a native lowering strategy and defined direct-backend comparisons satisfying the zero-abstraction-overhead constraint in ADR 0011; account explicitly for lifetime/provenance checks and any unresolved conflict without treating scaffolds as native performance evidence;
- lattice reductions have agreed syntax requiring `within Host` or `within Accelerator`, explicit iteration granularity, and specified rank participation, lane folding, result type/precision, and empty-domain behavior;
- tensor and pointwise Field linear-algebra capabilities specify trace, determinant, squared norms, infinity norms, Hermitian outer products, and vector inner products, including nested tensor meaning, result shape/kind/precision, operand order, and Field Lattice association;
- focused positive and negative conformance checks cover those operations, readable versus WriteDiscard access, placement, and invalid operand combinations; additional primitives such as adjoint and conjugation are either included or explicitly scoped;
- accepted reduction examples are frozen before their native implementation, with their Milestone 2 acceptance assignments recorded; portable syntax and conformance use backend facilities through adapters, without implementing duplicate backend reduction algorithms;
- backend selection occurs outside Oracle A;
- focused compile-time tests reject incompatible-lattice indexing and illegal Field View access;
- Scalar Site and Packed Site accesses have distinct result types;
- every placement-sensitive Oracle A construct belongs to an explicit Execution Context;
- skeletal QEX and Grid adapters satisfy the same portable interface without conditional branches in Oracle A;
- generated and installed builds bind to one explicit configuration, including custom build directories and canonical backend aliases;
- fixture-based build tests cover configuration extraction, QEX list-valued settings, paths requiring shell quoting, generated files, and unsupported backends;
- supported toolchain downloads resolve, downloaded artifacts are verified, and backend source revisions are recorded precisely enough to reproduce and inspect a build;
- direct backend selection rejects QUDA until a QUDA adapter satisfies the portable interface; and
- the final simplicity and base-module unit-test audits below are complete, their Milestone 1 findings are resolved, and `nimble verify` is green.

### Final audits before Milestone 2

Perform these audits after the Milestone 1 interface and conformance work is complete, in this order. Record findings, changes, retained design choices, and verification evidence in the milestone closeout. Both audits are required for Milestone 1 completion; repeat affected portions if subsequent changes invalidate their findings.

1. **Simplicity audit.** Review the portable interface, conformance scaffolds, and module organization for redundant types, duplicated logic or metadata, unnecessary wrappers and indirection, and opportunities to consolidate code. Apply simplifications that make the design easier to understand and maintain while preserving the accepted contracts, frozen oracles, backend-neutral interface, native-backend delegation, and zero-abstraction-overhead constraint. Judge compaction by reduced conceptual complexity rather than line count. Record why any apparently redundant structure remains necessary, and resolve actionable Milestone 1 findings before proceeding.
2. **Base-module unit-test audit.** Inventory every module under `src/quark/base`, including modules added during Milestone 1, and map its public contracts and enforceable invariants to meaningful tests. Check positive behavior, malformed-conformance and rejection cases, boundary conditions, result kind/precision/shape, and scope/provenance/access semantics where applicable. Fill gaps using self-contained `when isMainModule` tests with backend-independent fixtures; keep cross-module and integration tests under `tests/`. Confirm every source-local suite runs in `nimble verify`. Record coverage and resolved gaps per module, distinguishing native execution/performance evidence assigned to Milestone 2 from missing Milestone 1 unit coverage. Test counts alone do not establish completeness.

## Milestone 2 — QEX and Grid implementation, bottom up

Status: pending Milestone 1 completion; native integration has not started. First settle and verify the reopened portable contracts above, then Step 1 with Oracle D and native lifecycle evidence.

Implement the portable capabilities specified by the user-authored Milestone 2 oracles through QEX's and Grid's existing facilities, working through the same layers in both adapters. This combines the former backend-specific Milestones 2 and 3. Each step is complete only when both adapters pass its assigned frozen oracles and retain all earlier oracle acceptance. Track progress by step, oracle, and backend. Findings from either adapter inform the shared interface before building further on it.

The sequence below organizes implementation dependencies. As the user supplies and accepts further oracles, record their step assignments and required checks here. Those oracles determine each step's capability scope, including tensor or other capabilities they introduce. Oracle A remains part of the integrated acceptance set. Milestone 2 is complete only when the entire oracle set assigned to it passes on both adapters; acceptance happens during this milestone.

QEX and Grid continue to own concrete types, storage, access, and execution machinery. Reuse Grim where it faithfully realizes Quark's Grid interface, adapting or replacing it where required. Unsupported combinations reject explicitly. This sequence governs backend integration once the reopened Milestone 1 is complete.

### Step 1 — Initialization and finalization

- Oracle D builds, links, and runs in its normal, early-return, and exception variants against each configured backend.
- The adapter initializes its backend before the program body and finalizes it after scoped resources are released, including on normal Nim exception unwinding.
- Focused lifecycle checks establish call ordering and cleanup using each backend's actual runtime facilities.

### Step 2 — Lattice and site iteration

- Lattice construction uses the backend's geometry and layout facilities, including the concrete numeric/layout choices needed to resolve packing.
- Geometry, rank and packed partitions, dimensions, volume, and directions reflect that resolved Lattice.
- Scalar Site and Packed Site iteration use the intended backend iteration spaces and retain distinct index types and Lattice provenance.
- Shared portable tests check construction, conformability, iteration coverage, and rejection of unsupported layout requests. Oracle E establishes this step's Full/parity geometry and iteration acceptance; Oracle B adds complete parity Field acceptance in Step 4.

### Step 3 — Execution Contexts and Parallel Site Loops

- Host Parallel Site Loops use QEX `threads` regions containing ordinary Nim loops and Grid `thread_for`.
- Accelerator Parallel Site Loops use QEX's documented native accelerator iteration mechanism and Grid `accelerator_for`. Identify and verify the QEX mechanism during this step; the adapter must preserve the Accelerator Execution Context.
- Oracle F states both contexts and granularities without depending on completed Quark Fields. Backend probes establish native execution/coverage; generated-code inspection is required even when the source-level assertions pass with scaffolding.
- Focused tests inspect expanded/generated Nim for QEX and generated C++ for Grid. Accelerator constructs must be generated and inspected even when GPU hardware is unavailable, as specified by the Oracle A endpoint.

### Step 4 — Fields, Views, and site access

- Concrete Fields use backend-provided storage with shared-handle semantics and immutable Lattice association.
- Field Views select the corresponding backend host or accelerator access mechanisms for Read, ReadWrite, and WriteDiscard, synchronize as required, and close at scope exit.
- Site access preserves the declared numeric algebra and precision, distinct Scalar/Packed value types, access permissions, and Lattice provenance.
- Whole-Field initialization and assignment, indexed arithmetic, directions, sequences of Fields, and further oracle-specified Field capabilities use the execution and iteration facilities established above.
- Implement the tensor/Field linear algebra and lattice reductions settled in Milestone 1 through backend facilities, including native host/accelerator accumulation and communicator collectives. Assign the new accepted oracles to this step before implementation and retain cumulative acceptance.
- Oracles A, B, and C compile and pass with QEX and Grid while D, E, and F remain green with their required native evidence. Focused tests inspect the required view and loop constructs. Tensor-valued Field behavior follows the agreed tensor contracts and the additional oracles that specify its acceptance.

Completion requires all four steps and the complete cumulative Milestone 2 oracle suite to pass for both adapters. Keep focused positive, negative, numerical, and generated-code checks alongside each step. Existing Oracle A requirements for CPU builds and accelerator generated-code inspection remain in force; record any additional execution requirements with the oracles introducing them.

Every step also requires zero-abstraction-overhead evidence for its native capabilities under ADR 0011: retain equivalent direct-backend references, inspect optimized code and runtime operation/storage counts, and record the backend/toolchain configuration. This includes extra allocations, reference-count work, transfers, synchronization, and kernel/collective launches outside site loops as well as work inside them. Preserve all semantic guarantees. A capability with unexplained additional cost remains incomplete; an explicitly unsupported combination cannot count as passing a required oracle.

## Milestone 3 — Regression and acceptance infrastructure hardening

Harden the infrastructure and diagnostics around the oracle suite already passing at Milestone 2 completion. This retains the broader hardening work from the former Milestone 4; each Milestone 2 step has already established its own oracle acceptance.

Completion criteria:

- the cumulative oracle acceptance matrix for QEX and Grid runs from one project command;
- focused negative tests cover every enforceable governing invariant exercised by the accepted oracles;
- numerical results agree across adapters;
- generated-code checks pin the required parallel-loop and view constructs without pinning irrelevant formatting;
- zero-abstraction-overhead regressions are checked against the native references established in Milestone 2, with reproducible build configurations and representative performance measurements supporting code and operation-count evidence;
- setup and failure diagnostics identify the selected backend and missing capabilities clearly; and
- all project checks, oracle checksums, and repository hygiene checks pass.
