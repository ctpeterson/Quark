# Milestone 1 to Milestone 2 handoff

Date: 2026-09-12

Current status: Milestone 1 has been reopened at the user's request for lattice-reduction syntax and tensor/Field linear-algebra conformance. Milestone 2 native integration remains pending. The [roadmap](../../ROADMAP.md#milestone-1--portable-interface-and-backend-seam) is authoritative; the evidence below records the earlier closeout and cleanup. See [backend reduction research](../research/grid-qex-reductions.md) and [interface proposals](reduction-interface.md) for the new work. The compound numeric concept has been renamed from `Number[P]` to `Numeric[P]`.

Milestone 1 closed against its then-frozen interface; [the closeout note](milestone-1-closeout.md) records that evidence. The user subsequently requested source cleanup and an expanded Oracle A before starting native backend integration. This note records that intervening work and the additional conformance work exposed by the revised oracle. Milestone 2 remains the backend integration milestone; none of this work establishes native numerical execution.

## Accepted architecture after reopening

ADRs [0007](../adr/0007-scope-lattice-reductions-to-execution-contexts.md) and [0008](../adr/0008-separate-tensor-algebra-from-lattice-reductions.md) record scoped reductions and pointwise tensor/Field algebra, including vector inner products. ADRs [0009](../adr/0009-separate-tensor-descriptions-from-native-values.md) and [0010](../adr/0010-parameterize-site-kind-statically.md) separate mathematical tensor descriptions from native representations and select one static-kind Site family. Their production migration remains Milestone 1 work. Reduction spelling, infinity norms, and the other explicitly open algebra/collective details still require decisions.

[ADR 0011](../adr/0011-require-zero-abstraction-overhead.md) establishes zero abstraction overhead as a central constraint, now enforced by the project thesis, governing invariants, and roadmap acceptance criteria. Native implementation must supply equivalent direct-backend comparisons while retaining lifetime and provenance semantics. Historical scaffold tests do not establish that performance property.

## Completed cleanup

- Simplified tensor classification: ordinary tensors need no `UntaggedSpace` or `SpinSpace` objects. Spin types expose `isSpin = true`; structure and arithmetic preserve spin identity recursively through `SpinObject`.
- Made `within` introduce a lexical scope. View owners close exactly once on lexical exit or exception unwinding; copied Views and Site Proxies cannot extend their lifetime. The scope/owner machinery lives in `base/execution.nim`, following the Grid model and [ADR 0006](../adr/0006-bind-view-access-to-lexical-scopes.md).
- Retained Lattice provenance in Scalar and Packed indices, with incompatible Domain kinds rejected at compilation and incompatible Geometry/Layout instances rejected before access.
- Established source-local unit tests under `when isMainModule`, registered in `nimble verify`. Integration tests, cross-module fixtures, and harness scripts remain in `tests/`.
- Made every base module's tests independent of backend imports and backend selection. In particular, `iteration.nim` now uses a local Lattice witness. `AGENTS.md` records the dependency boundary.
- Kept unconditional static conformance checks at the end of concrete backend implementation modules. Backend unit-test expansion remains deferred until scaffold replacement.
- Moved shared Field scaffolding to `backend/common/commonField.nim`, updating both adapters and its documentation.
- Folded `showConfig.nim` into `build/configuration.nim`'s main-module entry point. `nimble config` produces the same report. These source moves require no reconfiguration of `local/qex` or `local/grid`; their build scripts discover source targets dynamically.

The expanded base suites contain 192 named tests:

| Module | Tests | Principal coverage |
| --- | ---: | --- |
| `lattice` | 25 | Geometry/Partition signatures, Domain classification, volume, directions |
| `numeric` | 32 | All promotion pairs, numeric classification, missing or incompatible arithmetic |
| `tensor` | 39 | Static shapes, nested components, arithmetic, scaling order, spin preservation |
| `execution` | 23 | Lexical visibility, nested contexts, owner copies, early exits, exactly-once cleanup |
| `iteration` | 17 | Site type and instance provenance, placement/granularity combinations, loop behavior |
| `field` | 56 | Numeric families, mode-correct views, proxy metadata, recursive write-only tensors |

All 192 passed during cleanup. The other 32 harness invocations also passed when run separately against both adapters. The full rig was then stopped by user edits to the frozen oracle files that had not yet been recorded in the manifest. Those historical results must not be read as acceptance of the expanded Oracle A below.

## Reading the Oracle A additions

The new examples ask for ordinary pointwise numeric algebra through indexed Field Views: Field Site Proxies, concrete Complex scalars, and literals participate in the same expressions; results remain chainable; compound updates consume existing destination values. Parentheses, operand order, and ordinary Nim precedence retain their meaning. This does not introduce whole-Field expression trees, reductions, or tensor division.

The refinement preserves the initial accelerator initialization, Packed computation, Host Scalar assertions, directions, and sequence-of-Fields program. It strengthens the new material by:

- verifying each copy and increment before the next operation can hide a failure;
- using `A = 2 + 4i`, `B = 3 - 2i`, and `number = 1 + i` for the arithmetic cases;
- making every denominator nonzero, correcting the incoming `(B - 2.0)` divisor when B still held `2.0`;
- checking 18 expressions separately, including reverse operand order, unary signs, multiplication precedence, and both division groupings;
- observing the `+=`, `-=`, `*=`, and `/=` update stages individually;
- checking that arithmetic leaves source Fields and existing sequence entries unchanged; and
- pairing positive updates with rejection of Read updates, WriteDiscard updates, and WriteDiscard reads.

Each result is read through a fresh Host Scalar view after the preceding view closes. Expected components are independent constants. All 18 expression results were checked with exact rational complex arithmetic, including nonzero divisors; the compound-update sequence has expected values `2+4i`, `5+2i`, `4+i`, `8+2i`, and `(20+22i)/13`. The verification helper uses a per-component absolute tolerance of `1e-12` for these bounded double-precision inputs. This is an oracle-specific accuracy requirement, not a general policy for arbitrary magnitudes or precisions. The checks use `doAssert` so the new numerical evidence remains required in release builds.

Explicit rank/packed construction remains a documented example. Turning its four-rank configuration into an unconditional allocation here would impose a new MPI launch and packing requirement on the default oracle; that belongs in a separately assigned layout oracle.

## Additional conformance work before integration

The incoming user-edited Oracle A already failed to type-check because scalar and Complex `+=` operands were not supported. The expanded oracle exposes the following matching gaps in both adapters:

| Requirement | Current scaffold evidence | Follow-up |
| --- | --- | --- |
| Site expressions with numeric scalars and literals | Chained assignment type-checks | Preserve the existing arithmetic and promotion checks during implementation |
| `+=` with a literal or a concrete Complex | Rejects; only Site Proxy/expression operands are accepted | Complete the operand-pair conformance surface |
| `-=`, `*=`, `/=` on ReadWrite sites | Rejects | Add compatible-result and permission checks, including negative counterparts |
| Host Scalar real `abs` and `<=` against a literal | Rejects | Supply the scalar numerical observation needed by the oracle; do not infer Packed comparison/reduction semantics from this requirement |
| Numerical storage, synchronization, and native execution | Still scaffolding | Implement in the assigned Milestone 2 steps; type-checking alone is insufficient |

`FieldSiteProxy` checks readable algebra and access metadata; matching it does not establish every assignment/update operand pair or numerical observation operation. These gaps are reasons to strengthen focused portable/adaptor conformance checks, not to introduce a new general expression framework.

Final verification: the freeze manifest passes, and `nimble verify` passes the build fixtures and all 192 base-module unit tests before stopping at the QEX Oracle A type check. Oracle A was also checked separately with Grid; both adapters fail on the unsupported operations above. No adapter code or harness requirement was changed to hide these failures. `nimble verify` must continue to check Oracle A; the expanded requirement creates a concrete pre-integration conformance backlog rather than retroactively invalidating the original Milestone 1 closeout.

The [oracle change record](../oracle-changes.md) records the user's authorization and updated hashes. Oracle B's source is unchanged in this pass; its prior hash is recovered exactly by changing the user's method-call constructor spelling back to the equivalent function-call spelling. At that point Oracle C was an unfinished, unfrozen tensor draft; the subsequent expansion below freezes it.

## Further oracle expansion priorities

1. **The early Milestone 2 steps.** Add small lifecycle, geometry/iteration, and execution-placement oracles that can pass before Fields exist. Check initialization/finalization ordering, resolved partitions, iteration coverage, and native loop constructs. Keep Oracle A as the Step 4 integrated endpoint. Explicitly assign Oracle B's parity construction and complete Field acceptance to the appropriate checkpoints.
2. **Nonuniform sites and packing.** Constant-valued Fields cannot detect lane permutations or duplicated/missed sites reliably. Agree how portable source obtains coordinates or a layout-independent site identity, then seed distinguishable values and verify Scalar/Packed agreement, rank-local coverage, and nontrivial partitions. State the required MPI rank count and supported packing for each run.
3. **Preservation, aliases, and lifetime.** Exercise partial ReadWrite updates, handle aliasing versus independent Field allocation and `:=`, self-referential site updates, and Host/Accelerator round trips. Carry nested-scope, early-return, and exception tests through real native Views. Decide the policy for simultaneously open conflicting Views before writing acceptance assertions for it.
4. **Numeric families and precision.** Add Real and Integer Fields, integer `div`/`mod`, Single/Double promotion, both operand orders, and explicit rejection of unsupported Half precision. Settle narrowing-on-assignment and exceptional arithmetic before adding cases that depend on either. Define tolerances for the tested values and precision rather than copying the double-precision bound everywhere.
5. **Oracle C's tensor contract.** Settle concrete Vector/Matrix/Spin construction syntax; cover nested spin-colour components, recursive access modes, matrix-vector products, and noncommuting matrix products. Check canonical backend physics-type compatibility as well as structural conformance. Numeric `/` must not silently become componentwise matrix division.
6. **Later numerical capabilities.** Reductions, conjugation/adjoints, shifts, halo exchange, and boundary conditions deserve dedicated oracles once their portable APIs and milestone assignments are agreed. They should not enter Oracle A as incidental arithmetic examples.

Every negative oracle case needs a nearby supported counterpart or a focused positive fixture; rejection caused by an entirely missing operation is not evidence that its permission or provenance rules work.


## Expanded suite and module documentation

The subsequent user request completed the proposed A/B/C expansion and established D/E/F for the earlier integration steps. [The oracle matrix](../../oracle/README.md) is now authoritative for file contents and cumulative assignments. The earlier priority list records the discussion leading to this expansion; C is no longer an unfrozen draft.

A now tests mixed numeric Kinds and S/D precision explicitly, including intermediate result types, nonuniform rank-local patterns, partial updates, aliases versus value copies, and early exits. B adds repeated selections, same-domain positives, parity data and arithmetic, and instance rejection. C follows the user's concrete Vector/Matrix/Spin declarations through numerical vector/matrix algebra, noncommuting products, matrix-vector contractions, nested spin-colour Fields, and recursive permissions/lifetimes. D covers three lifecycle exit paths, E Full/parity geometry and iteration, and F both execution contexts and granularities.

Native functionality and validation are delegated to the backend wherever it provides them. E observes exposed geometry and enumeration; it does not implement a partition validator. No coordinate API, narrowing policy, conflicting-view policy, or new reduction/halo API was introduced to fill a test case.

All six base modules now contain detailed `##` documentation immediately after their existing license headers. The descriptions cover public contracts, relationships between modules, and the limits of structural conformance. All six HTML pages render with Nim's documentation generator. `AGENTS.md` records this documentation convention and the backend-delegation rule.

The freeze manifest now covers A–F. The test rig registers all six syntax checks and all three D variants. Direct checks find the expected current gaps: A/B numeric observation and additional Field operations, and C's missing concrete tensor families. D's three language-level exit cases pass on both adapters, and E/F type-check; native lifecycle, iteration, and lowering acceptance remain pending their assigned steps.

Final verification of this expansion: all six hashes pass, all 192 base unit tests pass, and all six module documentation pages render without diagnostics. `nimble verify` remains red at Oracle A because the current scaffolds lack its observation and update operations, including integer-site comparison with an integer literal. The compiler emits additional cascading diagnostics after that missing comparison; Nim parser checks of all six sources pass. Separate checks cover both adapters for A–F and all three D exit variants as described above.
