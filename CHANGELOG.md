# Changelog

All notable changes to Quark are recorded here. The format is based on [Keep a Changelog](https://keepachangelog.com/), and releases follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Required final Milestone 1 simplicity and unit-test audits, including resolution of coverage gaps in every `src/quark/base` module before Milestone 2 begins.
- Accepted ADRs for scoped lattice reductions, pointwise tensor/Field linear algebra, mathematical tensor descriptions, a static-kind Site family, and zero abstraction overhead. Made zero abstraction overhead explicit in the project thesis, governing invariants, vocabulary, and native acceptance criteria; reduction spelling and remaining algebra details are still open.
- Required vector Hermitian inner products in the reopened Milestone 1 scope; documented proposals for mathematical tensor descriptions, a static-kind `Site` family, and verification of abstraction overhead.
- Comprehensive mixed-numeric, parity, and tensor acceptance cases in Oracles A–C, plus lifecycle, geometry/iteration, and execution-intent Oracles D–F with cumulative milestone assignments.
- Detailed module-level API documentation for all six portable base modules, verified through Nim HTML documentation generation.
- Vector and square-matrix structure and arithmetic concepts, recursive component conformance, and Spin-tag classification. Independent fixtures check static dimensions, spin preservation, readable access, and distinct arithmetic-result representations against both adapters' numeric families.

- Documented tensor compatibility with QEX/Grid physics operators and the proposed shape, component, and algebra contracts for `base/tensor.nim`.

- Field classification and separate constructor conformance, with shared-handle QEX/Grid scaffolds and focused positive and negative view/proxy metadata tests.

- Instance-based Lattice conformability and Full selection in the QEX and Grid conformance scaffolds, with independent kind parameters for comparisons.
- Backend-neutral `Geometry`, `Partition`, and `Lattice` interfaces with QEX and Grid conformance scaffolds.
- Portable numeric kinds, precisions, closed arithmetic capabilities, and mixed-kind promotion.
- A frozen Oracle B contract for immutable Domains and Field support with Lattice provenance.
- Compile-time backend selection and an experimental bootstrap, configure, and generated-Makefile workflow for backend toolchains.
- Compile-time reporting of the selected build configuration.
- Focused lattice and numeric conformance tests run against both QEX and Grid by `nimble verify`.

### Changed

- Renamed the compound `Number[P]` concept to `Numeric[P]`, retaining the individual Integer/Real/Complex concept names.
- Reopened Milestone 1 for execution-context-scoped lattice reductions and tensor/Field linear-algebra conformance. Recorded QEX/Grid source research and syntax proposals; native integration remains Milestone 2 work.
- Expanded Oracle A with separately verified complex site arithmetic, scalar and proxy compound updates, access-mode rejection, and Host readback. Corrected a zero-divisor example, refreshed the authorized oracle hashes, and recorded the resulting pre-Milestone-2 conformance gaps and cleanup in the handoff note.
- Folded configuration reporting into `build/configuration.nim`; `nimble config` uses that module directly.
- Expanded all six portable base modules' self-contained unit suites, including numeric and tensor capability rejection, recursive Field proxy modes, site provenance, and view lifetime edge cases. Base module tests use independent local fixtures and run without backend selection in `nimble verify`.
- Moved the shared Field scaffold to `backend/common/commonField.nim` and updated both adapters' imports.

- Established source-local `when isMainModule` unit tests and final, unconditional backend conformance blocks as development standards. `nimble verify` now runs the execution, iteration, and backend Lattice/Numeric entry points alongside the existing source-local Lattice tests; lifetime unit tests live in `execution.nim`.

- Enforced explicit Execution Contexts for Field Views, indexed access, and Parallel Site Loops. Scoped views close once on lexical exit and exception unwinding; copied views and Site Proxies cannot extend their access lifetime.
- Made Scalar and Packed Site Indices retain their originating Lattice, rejecting incompatible kinds at compile time and incompatible Geometry/Layout instances before access.
- Recorded refreshed toolchain URL, cached-archive checksum, and backend source-identity evidence for Milestone 1 closeout.

- Simplified tensor conformance by removing index-space marker objects and mandatory tag metadata. Only spin types expose `isSpin = true`; arithmetic and Field components retain spin identity through `SpinObject`.

- Combined the QEX and Grid implementation milestones into one shared sequence: initialization/finalization, Lattice and site iteration, parallel execution, then Fields and Views. User-authored frozen oracles define each step's acceptance; both adapters must pass the new and all earlier accepted oracles. Milestone 3 hardens the cumulative regression and acceptance infrastructure.

- Extended `FieldSiteProxy` to vector and square-matrix algebra, including nested tagged tensors. Component proxies recursively preserve access mode and Scalar/Packed index type; WriteDiscard requires component handles without readable arithmetic.

- Established `Spin[...]` as a mathematical index-space tag around a vector or matrix.

- Refined `FieldSiteProxy` to enforce readable numeric algebra at the site type's precision, with access-qualified conformance and focused result-kind, chaining, and Scalar/Packed checks. Documented a source-based Grid/QEX Spin representation recommendation for the future tensor contract.

- Recorded the Field Site Proxy algebra rule: site types determine numeric/vector/tensor capabilities, and component access preserves view permissions and site granularity. Concrete numeric representations are adapter-selected for the execution context.

- Clarified Milestone 1 as portable contracts and adapter conformance, with later milestones connecting to backend-provided storage and execution. Superseded the early native-experiment recommendation in the development notes.

- Made `FieldView[T, Mode]` a concrete adapter-owned type satisfying `FieldViewObject[T]`, with static access modes and inferred Lattice types. Recorded the user-authored Oracle A inference revision and refreshed its freeze checksum.

- Reduced `base/field.nim` to Field/view/site classification and access modes; deferred whole-Field expression machinery. Internal adapter placeholders preserve Oracle A syntax checks and explicitly reject unimplemented Field operations at runtime.

- Renamed Field construction to `newField(T)` and Lattice selection to `newSublattice`; `domain` now queries the `Domain` classification and `Decomposition` names the derived classification enum. Updated both frozen oracles with the user-authorized naming changes.

- Established shared Field-handle ownership: ordinary copies alias storage, while Whole-Field Assignment writes destination values.
- Revised Oracle B and ADR 0003 so Domain selections are Lattices with immutable kinds, removing the separate Decomposition and Domain concepts.
- Required direct constructors and parity selectors only for Full Lattices, with derived-result conformance and kind checks; added focused tests for cross-type comparisons and invalid adapters.
- Clarified Lattice conformability through matching kinds and shared Geometry and resolved Layout instances.
- Organized portable interfaces, backend adapters, and build configuration under explicit `base`, `backend`, and `build` seams.
- Standardized Nim source headers and added native documentation comments for settled portable interfaces.
- Recorded build-system hardening as a Milestone 1 requirement in ADR 0004.

### Fixed

- Explicitly checked that every supported `newLattice` constructor form produces kind Full, independently of Lattice concept matching.
- Repaired stale decomposition imports and fixtures after merging Domain properties into Lattice, and removed same-concrete-type constraints on derived selections.
- Bound generated and installed builds to their exact configuration, fixed selector aliases and path quoting, and rejected QUDA as a direct adapter.
- Preserved QEX list settings and configuration values through JSON string encoding, with backend-owned readers and offline build-contract tests.
- Corrected LLVM artifact locations, pinned archive SHA-256 checksums, and recorded source commits, patches, toolchain identities, and dependency fallback provenance.

- Restored the frozen Oracle A checksum and added Oracle B to the freeze manifest.
