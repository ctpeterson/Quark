# Quark development instructions

## Project thesis

Quark makes lattice-field-theory programs portable across established high-performance codebases by expressing lattice geometry, fields, site access, views, and execution intent once in ordinary Nim. Portability must preserve the low-level layout and execution choices needed to understand generated code and performance.

Zero abstraction overhead is a central design constraint: Quark must add no runtime work or storage compared with an equivalent direct-backend program preserving the same semantics. Treat this as an acceptance requirement, not a later optimization; [ADR 0011](docs/adr/0011-require-zero-abstraction-overhead.md) defines the comparison and required evidence.

Quark owns the portable semantics. Systems such as QEX and Grid provide native storage and execution machinery. Backend adapters supply concrete Quark-facing types and connect portable operations to those backend facilities, including build integration. When a backend already implements an operation or validation, delegate to that facility; Quark owns the portable meaning and adapter conformance, not a duplicate implementation.

Quark is a regular Nim project. Nim remains the authority for general syntax, typing, macros, compilation, and C/C++ interoperability; see `docs/adr/0001-use-nim-as-the-language-and-toolchain.md`.

## Start here

Before changing Quark semantics or a backend adapter, read `CONTEXT.md`, the relevant ADRs under `docs/adr/`, the frozen oracles under `oracle/`, and the active milestone in `ROADMAP.md`.

Use the active milestone's scope and completion criteria to choose work and report progress. `ROADMAP.md` → Milestone 1 defines the separation between contract/conformance work and later backend integration; exploratory notes and checkpoints do not advance that schedule.

When changing the portable type interface or adapter conformance checks, also read `docs/notes/nim-concepts-at-the-portable-interface.md` for the current Nim-concepts experiment and its limits.

When designing an interface or changing native lowering, read [ADR 0011](docs/adr/0011-require-zero-abstraction-overhead.md). During Milestone 2, compare optimized generated code and runtime operations with a direct-backend reference as part of each capability's acceptance.

Record notable user-visible changes under `CHANGELOG.md` → `Unreleased`. When preparing or tagging a release, read `docs/RELEASING.md`; `quark.nimble` is the authoritative version source.

## Session efficiency

Treat the repository as the durable memory between sessions. Begin resumed work by inspecting `git status`, the relevant diff, and the active milestone; continue from that state instead of reconstructing completed work from conversation history.

- Use `rg` and targeted line ranges or symbols. Read a complete file when its whole content governs the task, but do not repeatedly reread unchanged files during the same task.
- Keep command output bounded. Prefer quiet modes and focused failure excerpts; retain full logs in a temporary file when they may be needed rather than placing them all in conversation context.
- Run the narrowest meaningful check while iterating. Run `nimble verify` when the coherent change is ready, and repeat broad checks only after relevant edits, a failure, or an unresolved concern.
- Keep progress updates brief and report new findings or changed state rather than restating the plan or settled context.

## Source documentation

Every Nim file under `src/` begins with the non-documenting `#[ ... ]#` header used by `src/quark/base/lattice.nim`, including its path relative to `src/`. Reserve Nim's `##` documentation comments for settled public interfaces; describe their portable semantics and invariants without backend implementation details. Each base module follows its license header with detailed module-level `##` documentation covering its role, contracts, relationships, and limits.

## Tests and adapter conformance

- Put self-contained unit tests in the source module they test, under `when isMainModule`, with test-only imports inside that guard. Keep integration tests, cross-module conformance fixtures, compiler-rejection programs, and harness scripts under `tests/`.
- Keep `src/quark/base` independent of `src/quark/backend`, including main-module tests. Use local contract fixtures in base modules; put tests that import adapters or the `quark` umbrella module under `tests/`.
- Register every source module with main-module unit tests in `quark.nimble` → `verify`. Run backend-dependent portable tests against both QEX and Grid, and each backend's own module tests with that backend selected explicitly.
- End each backend implementation module with an unconditional `static:` block asserting conformance of its concrete types and operations to the portable interface. Keep these assertions outside `when isMainModule` so ordinary imports enforce them too. Modules that only re-export implementations rely on those implementations' checks.

## Governing invariants

1. **Frozen oracles drive design.** Once accepted, an oracle is immutable input to implementation work. Quark and its adapters move toward the oracle; the oracle does not move to make an implementation pass.
2. **One source means one program.** A portable oracle contains no backend-selection branches. The same file is compiled against every supported backend in its acceptance matrix.
3. **Performance intent stays explicit.** Execution Context, iteration space, Field View, and access mode remain visible in Quark source when they affect lowering, data movement, or generated-code shape.
4. **Lattices and Fields remain distinct.** A Lattice owns geometry and layout. Fields are associated with a Lattice but are separate values and storage.
5. **Site Indices carry provenance.** A Site Index is valid only for Fields associated with a conformable Lattice as defined in `CONTEXT.md`. Indexing across incompatible kinds or Geometry/Layout instances rejects.
6. **Index kind determines access type.** A Scalar Site produces one scalar site value; a Packed Site produces one layout-packed site value.
7. **Field Views are scoped and access-qualified.** `Read`, `ReadWrite`, and `WriteDiscard` retain the meanings in `CONTEXT.md`. Backend erasure of a view must preserve those semantics.
8. **Parallel lowering follows Execution Context.** Each backend maps a Parallel Site Loop to its native host or accelerator construct. The mapping is a requirement, not an optimization hint.
9. **Unsupported semantics reject explicitly.** An adapter reports an unsupported combination instead of silently changing iteration space, execution placement, access mode, precision, or layout.
10. **Lowering remains inspectable and deterministic.** Identical Quark source, backend configuration, and toolchain produce equivalent generated code. Tests inspect required backend constructs as well as numerical results.
11. **The portable interface stays backend-neutral.** QEX, Grid, QUDA, and other backend types stay behind adapters unless an explicitly backend-specific escape hatch is introduced and named as such.
12. **Abstractions have zero overhead.** Static descriptions and execution/access choices erase; native lowering adds no work or storage beyond equivalent backend code. Preserve lifetime, provenance, precision, and placement guarantees while demonstrating this property under ADR 0011; scaffold conformance alone is insufficient.

## Oracle discipline

`oracle/oracles.sha256` is the freeze manifest. `nimble verify` checks it before compiling implementation code.

- Add capability through a new oracle rather than enlarging an accepted one.
- Add focused positive and negative tests beside implementation work; oracles are acceptance tests, not the entire test suite.
- If an accepted oracle is genuinely wrong, stop implementation work. Change it only with explicit user approval, record why, and update the freeze manifest in the same change. Record an ADR when the correction changes project semantics.
- Never weaken an assertion, access mode, iteration space, or execution context to obtain a green result.

## Architecture

The central seam is between Quark's portable interface and backend lowering:

```text
ordinary Nim + Quark constructs
            ↓
portable lattice semantics
            ↓
backend adapter
   ├── QEX
   └── Grid
```

Keep this interface small. Quark source states what must be preserved; an adapter concentrates all knowledge of how its backend realizes it. Test observable behavior and generated-code shape through the same interface users compile against.

## Change discipline

For each coherent change:

1. Name the active `ROADMAP.md` milestone and the completion criterion being advanced.
2. Run the existing checks and distinguish baseline failures from regressions.
3. Add or strengthen a focused test for the semantic step when feasible.
4. Implement the smallest change through the portable interface and adapter appropriate to the active milestone. For Milestone 1, this means contracts and conformance scaffolds.
5. Inspect generated or expanded code whenever lowering changes. For native implementation, retain the direct-backend comparison required by ADR 0011 and investigate any extra work or storage before declaring acceptance.
6. Run focused checks, then `nimble verify`.
7. Inspect `git diff --check`, the full diff, and repository status.
8. Update `CONTEXT.md` only when vocabulary changes, an ADR only when a durable trade-off is resolved, and `ROADMAP.md` when a milestone advances.

## Current objective

Follow the active milestone in `ROADMAP.md`: complete the portable interface, then implement QEX and Grid together through the user-authored oracles assigned to each Milestone 2 step. The roadmap's cumulative oracle acceptance rules and ordered completion criteria are authoritative.

## Definition of done

A milestone is done only when every completion criterion in `ROADMAP.md` for that milestone is observable and all its required checks are green. Preserve all frozen oracles; native backend acceptance must establish both the required constructs and zero abstraction overhead, with the evidence specified in ADR 0011.
