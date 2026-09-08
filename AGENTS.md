# Quark development instructions

## Project thesis

Quark makes lattice-field-theory programs portable across established high-performance codebases by expressing lattice geometry, fields, site access, views, and execution intent once in ordinary Nim. Portability must preserve the low-level layout and execution choices needed to understand generated code and performance.

Quark owns the portable semantics. Backend adapters own the concrete types, memory-access machinery, loop constructs, and build integration for systems such as QEX and Grid.

Quark is a regular Nim project. Nim remains the authority for general syntax, typing, macros, compilation, and C/C++ interoperability; see `docs/adr/0001-use-nim-as-the-language-and-toolchain.md`.

## Start here

Before changing Quark semantics or a backend adapter, read `CONTEXT.md`, the relevant ADRs under `docs/adr/`, the frozen oracles under `oracle/`, and the active milestone in `ROADMAP.md`.

When changing the portable type interface or adapter conformance checks, also read `docs/notes/nim-concepts-at-the-portable-interface.md` for the current Nim-concepts experiment and its limits.

Record notable user-visible changes under `CHANGELOG.md` → `Unreleased`. When preparing or tagging a release, read `docs/RELEASING.md`; `quark.nimble` is the authoritative version source.

## Session efficiency

Treat the repository as the durable memory between sessions. Begin resumed work by inspecting `git status`, the relevant diff, and the active milestone; continue from that state instead of reconstructing completed work from conversation history.

- Use `rg` and targeted line ranges or symbols. Read a complete file when its whole content governs the task, but do not repeatedly reread unchanged files during the same task.
- Keep command output bounded. Prefer quiet modes and focused failure excerpts; retain full logs in a temporary file when they may be needed rather than placing them all in conversation context.
- Run the narrowest meaningful check while iterating. Run `nimble verify` when the coherent change is ready, and repeat broad checks only after relevant edits, a failure, or an unresolved concern.
- Keep progress updates brief and report new findings or changed state rather than restating the plan or settled context.

## Source documentation

Every Nim file under `src/` begins with the non-documenting `#[ ... ]#` header used by `src/quark/base/lattice.nim`, including its path relative to `src/`. Reserve Nim's `##` documentation comments for settled public interfaces; describe their portable semantics and invariants without backend implementation details.

## Governing invariants

1. **Frozen oracles drive design.** Once accepted, an oracle is immutable input to implementation work. Quark and its adapters move toward the oracle; the oracle does not move to make an implementation pass.
2. **One source means one program.** A portable oracle contains no backend-selection branches. The same file is compiled against every supported backend in its acceptance matrix.
3. **Performance intent stays explicit.** Execution Context, iteration space, Field View, and access mode remain visible in Quark source when they affect lowering, data movement, or generated-code shape.
4. **Lattices and Fields remain distinct.** A Lattice owns geometry and layout. Fields are associated with a Lattice but are separate values and storage.
5. **Site Indices carry provenance.** A Site Index is valid only for Fields associated with the Lattice that produced it. Cross-lattice indexing rejects.
6. **Index kind determines access type.** A Scalar Site produces one scalar site value; a Packed Site produces one layout-packed site value.
7. **Field Views are scoped and access-qualified.** `Read`, `ReadWrite`, and `WriteDiscard` retain the meanings in `CONTEXT.md`. Backend erasure of a view must preserve those semantics.
8. **Parallel lowering follows Execution Context.** Each backend maps a Parallel Site Loop to its native host or accelerator construct. The mapping is a requirement, not an optimization hint.
9. **Unsupported semantics reject explicitly.** An adapter reports an unsupported combination instead of silently changing iteration space, execution placement, access mode, precision, or layout.
10. **Lowering remains inspectable and deterministic.** Identical Quark source, backend configuration, and toolchain produce equivalent generated code. Tests inspect required backend constructs as well as numerical results.
11. **The portable interface stays backend-neutral.** QEX, Grid, QUDA, and other backend types stay behind adapters unless an explicitly backend-specific escape hatch is introduced and named as such.

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
4. Implement the smallest vertical slice through the portable interface and the active adapter.
5. Inspect generated or expanded code whenever lowering changes.
6. Run focused checks, then `nimble verify`.
7. Inspect `git diff --check`, the full diff, and repository status.
8. Update `CONTEXT.md` only when vocabulary changes, an ADR only when a durable trade-off is resolved, and `ROADMAP.md` when a milestone advances.

## Current objective

Complete the frozen `oracle/oracleA.nim` against QEX and Grid. The ordered milestones and their completion criteria are authoritative in `ROADMAP.md`.

## Definition of done

A milestone is done only when every completion criterion in `ROADMAP.md` is observable, all required checks are green, the frozen oracle is unchanged, and the generated code preserves the required backend constructs.
