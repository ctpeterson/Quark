# Lattice reductions and tensor linear algebra

Date: 2026-09-12

Status: syntax proposals for the reopened Milestone 1, under the accepted [reduction](../adr/0007-scope-lattice-reductions-to-execution-contexts.md), [linear-algebra](../adr/0008-separate-tensor-algebra-from-lattice-reductions.md), and [zero-overhead](../adr/0011-require-zero-abstraction-overhead.md) decisions. The user requires reductions to live inside an Execution Context and requires scalar-valued tensor operations on Fields to produce Numeric-valued Fields. Those requirements are settled; the reduction spelling and remaining algebra details below are not an accepted API. The [QEX/Grid source report](../research/grid-qex-reductions.md) supplies the native evidence. Existing frozen oracles are unchanged.

## Separate site algebra from lattice reduction

`norm2(vector)` and `norm2(matrix)` contract the tensor at one site. Both backends define these as the sum of squared magnitudes of the numeric components: squared Euclidean norm for a vector and squared Frobenius norm, `tr(M†M)`, for a matrix. This is not the squared nuclear norm sometimes meant by “squared trace norm.” The same definition extends through nested tensor components.

In Quark, `norm2(field)`, `trace(field)`, and `det(field)` must apply the corresponding operation at each site, yielding Numeric-valued Fields on a conformable Lattice. Their mathematical Field results need not force intermediate allocation: an adapter can evaluate a Field expression through its native expression facilities. Representation and evaluation are still to be settled; this proposal does not restore the removed portable expression-tree implementation.

A lattice reduction explicitly combines the site results. This distinction matters because QEX's native `trace(Field)` already includes a global sum, while Grid exposes pointwise trace expressions. The QEX adapter must select site trace for Quark's pointwise operation, and only perform the global reduction when requested.

## Syntax candidates

All three candidates below parse with Nim 2.2.8 as ordinary macro calls. Each uses a read-qualified view, an explicit Lattice and Site Granularity, and the enclosing Execution Context. These are alternative interfaces, not three APIs proposed for simultaneous introduction.

### A: reducer block with an ordinary site loop — recommended

```nim
within Accelerator:
  let a = field.view(Read)
  let total = reduce(Sum):
    for n in lattice.sites(Packed):
      norm2(a[n])
```

The loop body's final expression supplies one contribution per site. The reduction owns parallel execution and returns a completed value; it does not require an additional `parallel` wrapper or mutation of a captured accumulator. `Sum`, `Max`, and `Min` select the combining operation, subject to its operand capabilities. A tensor-valued contribution can be summed without contracting its tensor indices.

The regular loop makes the binder and iteration space familiar. Additional per-site `let` bindings fit naturally. A first implementation can require exactly one site loop and a contribution on every path, rejecting `break`, early `return`, nested lattice collectives, and side effects outside the contribution computation rather than inventing ambiguous partial-reduction semantics.

### B: compact binder

```nim
within Accelerator:
  let a = field.view(Read)
  let total = reduce(Sum, n in lattice.sites(Packed)):
    norm2(a[n])
```

This removes a level of indentation. The macro must introduce the `n` binding from the untyped `in` expression; it is less directly an ordinary Nim loop but expresses the same contract.

### C: operation-named block

```nim
within Accelerator:
  let a = field.view(Read)
  let total = sum:
    for n in lattice.sites(Packed):
      norm2(a[n])
```

This is concise for common sums, with corresponding `maximum` and `minimum` blocks. Candidate A gives one obvious place for additional reducer controls and future combined reductions. Nim identifiers are style-insensitive, so an operation-named `sum` API and an unqualified enum member `Sum` would also need deliberate name resolution if both were ever exposed.

The tempting `let total = sum for n in ...:` does **not** parse in Nim 2.2.8. `parallel for` is a statement-level command; the same spelling cannot simply be used as this initializer expression. The three valid forms above were inspected as ASTs in a disposable macro fixture, not implemented as reductions.

## Proposed semantics to settle before implementation

- A reduction requires `within Host` or `within Accelerator`, just like a Parallel Site Loop. Host/Accelerator controls local computation, not which MPI ranks participate. The adapter selects a native path preserving that placement; build-selected default placement is insufficient.
- Make lattice-wide participation the default: combine every selected site across the Lattice's communicator and return the result to each participating rank. Provide a clearly named rank-local variant if needed. A global reduction must be encountered by participating ranks in compatible collective order; it cannot be invoked conditionally by an arbitrary subset or independently inside each parallel site iteration.
- `Scalar` and `Packed` must represent the same mathematical site coverage. Packed reduction folds lanes in addition to threads and ranks, preserving tensor components unless the site expression contracts them. No extra factor of the packing width is introduced.
- Return a completed owning value, usable after the view closes. Accelerator synchronization and any result transfer belong to the backend reduction path. Read permissions and conformability still apply to every input; WriteDiscard is not a readable reduction operand.
- Set accumulation precision independently from input storage and result storage. Native double return types do not prove double accumulation at every stage. A proposed explicit `accumulate = D` control must widen before accumulation, and document whether it also widens evaluation of the site expression; widening its result cannot undo arithmetic already done in S. Both the default and any explicit policy require conformance evidence. Integer exactness and overflow need a separate rule.
- Sum has a typed zero identity, including empty local partitions. For minimum/maximum, either require an explicit identity or specify a globally empty-domain error and a native participation protocol; never skip a collective because one rank has no local sites. Complex values have no implicit ordering. NaN behavior and floating summation tolerances must be specified, without promising bitwise equality across layouts or reduction trees.
- Start with the sum and real extrema needed by accepted examples. Fused pairs such as `(inner(x, y), norm2(x))` are useful, but a custom-reducer framework is unnecessary until its supported algebra and backend lowering are demonstrated. Slice/time-slice reductions need an explicit retained-geometry/result contract rather than masquerading as scalar reductions.

These are proposed portable requirements and adapter responsibilities, not a plan to implement independent MPI, thread, SIMD, or device reduction machinery in Quark. The native report identifies facilities that can be used directly and combinations that still need adapter investigation or explicit rejection.

## Tensor and Field capabilities

Use small operation capabilities and operand-pair checks; metadata-only tensor classification should not imply every operation exists. Readable site proxies and Field operations must expose the supported capability with the same mathematical meaning.

| Operation | Proposed site contract | Pointwise Field result |
| --- | --- | --- |
| `trace(m)` | Full trace of a square matrix; nested trace contracts all matrix index spaces | Numeric-valued Field, preserving the appropriate kind and precision |
| `det(m)` | Determinant of a square matrix; valid singular input has determinant zero | Numeric-valued Field; supported nested structures and numeric kinds must be explicit |
| `norm2(x)` | Sum of squared magnitudes over numeric leaves; both backends agree | Real-valued Field for Real/Complex leaves; Integer result/promotion remains to settle |
| `normInf(x)` | Vector maximum component magnitude; matrix definition remains open | Real-valued Field for Real/Complex leaves, on the same Lattice |
| `outer(v, w)` | Hermitian outer product `v * w†`, preserving operand order | Matrix-valued Field with promoted numeric leaves and conformable input Lattices |
| `inner(v, w)` | Required vector capability: Hermitian contraction `v†w`, conjugating the first operand | Numeric-valued Field; a lattice sum is separately requested |
| `adj(x)` / `conj(x)` | Suggested additions: adjoint and component conjugation with explicit shape/tag rules | Field of the corresponding site result |

The checked backends do not provide a shared generic tensor infinity-norm definition. Grid's `maxLocalNorm2(field)` computes a lattice maximum of site squared Euclidean/Frobenius norms; it is neither the matrix maximum-entry norm nor the induced infinity norm. Therefore native naming does not settle Quark's `normInf(matrix)`. Two coherent choices are maximum entry magnitude (consistent with recursively treating tensor leaves as a vector) and maximum absolute row sum (the induced matrix infinity norm). Keep the choice open rather than assigning a backend definition that does not exist.

Nested matrices require care beyond scalar leaves. Full trace and squared norm have recursive native formulations. Determinants of matrices with matrix-valued blocks are not obtained by taking determinants of individual blocks and then taking the determinant of those numbers. If the intended operation is the determinant of the flattened spin-colour linear operator, specify that explicitly and verify native support. Partial spin/colour traces return tensors, so they should be separately named operations rather than change `trace(Field)`'s required Numeric result.

Outer products must be checked with non-real values so a missing conjugation cannot pass. For nested vectors, specify which index spaces the product preserves and how they map to a nested matrix; successful plain-vector conformance does not establish spin-colour conformance. A vector's adjoint may require a dual expression rather than the same vector shape; avoid adding a row-vector representation solely to name the operation.

## Conformance and acceptance work

Milestone 1 must cover supported operation signatures and result kind, precision, tensor shape/tag, view permissions, Field association, and reduction context. Include malformed witnesses and operand pairs that would otherwise hide unsupported operations. Pointwise Field contracts belong at the Field seam; tensor algebra belongs at the tensor seam; neither imports a backend.

After syntax acceptance, add new frozen oracles for reductions and linear algebra, assigned to Milestone 2 Step 4. Numerical cases should distinguish tensor contraction from lattice combination, Scalar from Packed coverage, Full from parity selections, single from multiple ranks, and pointwise from global maxima. Use independent expected values, complex outer/inner products, non-diagonal matrices, singular matrices, and nonsingular matrices with a zero leading pivot. Include accumulation-sensitive floating inputs and exactly representable integer sums beyond `2^53` where supported. Test native placement and collective construction as well as results.

Source inspection found native limitations relevant to these tests: Grid's examined determinant uses unpivoted elimination; QEX's generic determinant has an unfinished singular-matrix path; QEX's generic integer communicator reduction passes through floating point. These are reasons to verify or explicitly reject an unsupported native path, not to relax the portable mathematical operation. The report records the exact source locations and the limits of this source-only evidence.

## Verification of this preparation

The `Number[P]` → `Numeric[P]` rename changes classification spelling only. Existing numeric classification tests already cover every kind/precision combination, wrong precisions, and rejection of unrelated types; tensor and Field suites exercise downstream concept matching. The reduction forms above were parsed with Nim 2.2.8. No reduction macro, linear-algebra conformance implementation, or new frozen oracle is claimed by this research/design preparation.

The focused numeric/tensor/Field suites pass all 127 tests after the rename. `nimble verify` before and after this change passes the oracle manifest, build fixtures, and all 192 base-module tests; including the QEX module suites it records 198 passing tests before stopping at the same expanded Oracle A failures. The first failure remains missing real-proxy `abs` at A:25; the baseline and final runs each report the same 78 compiler errors, including subsequent unsupported updates/comparisons and cascades. Logs are `/tmp/quark-reductions-baseline.log` and `/tmp/quark-reductions-verify.log`. This preparation introduces no new verification failure and does not claim the full rig is green.
