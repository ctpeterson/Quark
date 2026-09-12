# Frozen oracle changes

## 2026-09-12 — Complete the numeric, parity, tensor, and early-step oracles

The user requested the suggested expansion of the oracle suite, specifically mixed numeric arithmetic in A, a review and expansion of B, and a comprehensive C based on the user's concrete Vector/Matrix/Spin Field declarations. The user also clarified that native operations and validation belong to the backend wherever it already provides them. This pass adds no partition validator or backend algorithm to Quark.

A retains its previous cases and adds 20 Integer/Real/Complex operand-pair cases across S/D precision, two mixed chains, numerical and result-type assertions, positive integer `div`/`mod`, nonuniform rank-local data, partial ReadWrite preservation, all four placement/granularity combinations, Field handle aliases versus value-copy assignment, and normal/exceptional scope exits. Exactly representable Single inputs keep its stated Double observation tolerance meaningful. No narrowing or exceptional-arithmetic policy is invented.

B retains its original parity program and adds observations after each stage, repeated/equivalent selection, valid same-domain assignment and indexing, independent storage, nonuniform parity data, and incompatible kind/instance rejection. Layout construction, site selection, and their native validation remain backend responsibilities.

C preserves the user's `Vector[T, N]`, square `Matrix[T, N]`, and `Spin[T]` spellings. It adds numerical initialization, eight vector and seven matrix arithmetic cases each exercised for ordinary and Spin-tagged types, noncommuting matrix products, matrix-vector products, numeric Field coefficients, partial component updates, nested 4-spin/3-colour vectors and matrices, recursive permission rejection, and component lifetime checks. It is now frozen as an acceptance target; concrete tensor families and native support are still pending.

D, E, and F are new early-step inputs: one lifecycle per process with three exit variants; backend-resolved Full/parity geometry and iteration; and context/granularity/parallel intent independent of Field storage. D's native lifecycle trace and F's generated native loop inspection remain required in addition to their source assertions. The cumulative milestone assignments and observation requirements are in [oracle/README.md](../oracle/README.md).

The six base modules also gained detailed module-level `##` documentation, rendered successfully with Nim's documentation generator. Their executable implementation and unit-test bodies were not changed by this documentation pass.

All six oracle files parse with Nim's parser. Reference checks validate the mixed numeric constants, noncommuting matrix examples, matrix-vector result, and selected nested-leaf division. D's normal/return/raise control-flow variants pass with both adapters; E and F type-check. A/B fail the existing scalar-observation requirements, and C fails because the concrete tensor families are not implemented. None of those failures is hidden by changing oracle requirements.

Previous manifest:

```text
d75a427b02e323fc470ac740b6a94f9241c68845a79e86ff94daf9289191ec00  oracle/oracleA.nim
96ab7fad5c7bd693d62bca9cf35765d578cdd3122c11528a25bf7aecf593badb  oracle/oracleB.nim
```

Updated manifest:

```text
7daeead68c0204797cc004c6573761b278cc95b200e30750e23c80ce169b7ae2  oracle/oracleA.nim
8a6bf524a4ed50fa8bbf7dba844b3bb0a30054ba78eafca64a0305abee106562  oracle/oracleB.nim
4b44e554e4647e644d8f90961128a0699aac38a6c83ee4523863bd5bdc0d8153  oracle/oracleC.nim
08922f7310ed6daeafbd1cb0aba733a6ca5167e34c0e2403410ef2d728e230c9  oracle/oracleD.nim
938d11d0d72db26cc971f0b2a7e4a8c71637442b9d3061469a5c3c6a30c6b19a  oracle/oracleE.nim
c2b2849dd92ce0e76463547798beb689a6af308911466cb40721a068df7dd2fd  oracle/oracleF.nim
```

## 2026-09-12 — Expand Oracle A's pointwise numeric acceptance

The user explicitly requested refining and expanding the newest Oracle A additions before starting Milestone 2, including using that work to identify any remaining Milestone 1 conformance gaps. This authorizes revising the frozen oracle for a stronger contract; it is not a revision to accommodate the existing adapters.

Oracle A retains its initialization, contexts, iteration spaces, initial assertions, and sequence-of-Fields examples. Each added arithmetic and update result is now observed before another write can hide it. Distinct, non-real Complex inputs exercise cross terms; all divisors are nonzero. Eighteen checked expressions cover mixed scalar/site arithmetic, reverse operand order, unary signs, precedence, and division grouping. Separate ReadWrite stages cover `+=`, `-=`, `*=`, and `/=`; negative cases retain access restrictions. Host Scalar readback checks independently calculated components within `1e-12` for these bounded double-precision cases.

The incoming `(fieldBView[n] - 2.0)` divisor was zero because fieldB still held `2.0`; the arithmetic section now explicitly initializes `A = 2+4i`, `B = 3-2i`, and `number = 1+i`. The original initialization examples and assertions remain. Field division here means pointwise Real/Complex site division, not whole-Field expressions or tensor division.

Oracle B's current user-authored bytes are re-recorded without editing its source. Its previous checksum is reproduced exactly by replacing `[8, 8, 8, 16].newLattice()` with `newLattice([8, 8, 8, 16])`; that spelling change has no semantic effect. Oracle C is still a draft and is not added to the freeze manifest.

Both adapters currently fail Oracle A's type check on the missing compound-update and numerical-observation capabilities. The harness still requires the check. Native execution remains pending Milestone 2. The [handoff note](notes/milestone-1-to-2-handoff.md) records cleanup, verification, gaps, and proposed further oracles. No new representation or general arithmetic policy is chosen, so no additional ADR is needed.

Previous manifest:

```text
fa041034c62e231d0dc09a578109562dd9da941682d33d7187cc4df79278dae0  oracle/oracleA.nim
cdcd54f9d57a39973ccdcf4fc1f8d507e71da4f3eabbbe69802dff68596b1202  oracle/oracleB.nim
```

Updated manifest:

```text
d75a427b02e323fc470ac740b6a94f9241c68845a79e86ff94daf9289191ec00  oracle/oracleA.nim
96ab7fad5c7bd693d62bca9cf35765d578cdd3122c11528a25bf7aecf593badb  oracle/oracleB.nim
```

## 2026-09-11 — Infer concrete Field View types

The user removed Oracle A's eight `FieldView[Complex[D]]` annotations after choosing compile-time access-mode enforcement with concrete adapter-owned Field Views. Ordinary Nim inference retains the site type, static access mode, and Lattice type returned by `field.view(mode)`. Explicit annotations may use the adapter's concrete `FieldView[T, Mode]` family; `FieldViewObject[T]` remains the portable conformance concept. This replaces the delegating `FieldView[T]` concept without changing access permissions or execution semantics.

The user's oracle bytes are preserved. Numerical operations, assertions, access modes, iteration spaces, and execution contexts are unchanged, and Oracle B's manifest entry is unchanged. No new semantic trade-off is introduced.

The Oracle A checksum changed from `7a16bf053883fc71cefc26bce4cab6e1454752721c461482c2b9c9ef09191140` to `fa041034c62e231d0dc09a578109562dd9da941682d33d7187cc4df79278dae0`.

## 2026-09-10 — Field and sublattice constructor names

The user renamed Oracle A's Field constructor to `newField(T)` and Oracle B's parity selectors to `newSublattice`. The subsequent request to finish these changes authorized applying the same Field-constructor rename to Oracle B. This separates construction from the `domain` classification query and lets the Field's type argument specify its site value. Assertions, access modes, iteration spaces, execution contexts, and the existing Oracle B whitespace are preserved. No new semantic trade-off is introduced.

Previous manifest:

```text
34320efb23ffba9479bd17a35b6a61adfe4680f482c50a4f8daff50f0889d09a  oracle/oracleA.nim
bae708085fd6b3bd8854d5cc8a912cebcf28c7cefcc770f66a2461269d275b59  oracle/oracleB.nim
```

Updated manifest:

```text
7a16bf053883fc71cefc26bce4cab6e1454752721c461482c2b9c9ef09191140  oracle/oracleA.nim
cdcd54f9d57a39973ccdcf4fc1f8d507e71da4f3eabbbe69802dff68596b1202  oracle/oracleB.nim
```

## 2026-09-09 — Oracle B selections are Lattices

The user revised parity selections to carry `Lattice` annotations, removed the separate Domain concept, and made direct `newLattice` construction the Full case. The revised oracle omits explicit Full selection and the implicit-to-explicit Full Field assignment, while retaining the parity-volume assertions, incompatible assignment checks, cross-Domain indexing check, and explicit execution and access modes. These are user-authored contract revisions, not changes to obtain an implementation pass.

ADR 0003 now records one Lattice concept with immutable selection kinds, conditional Full constructors and parity selectors, and independently typed conformability operations. Full-to-parity construction is required by concept conformance; native parity construction and Field/iteration enforcement remain implementation work.

The freeze-manifest checksum changed from `79cfe99d94f3686a84bd4a2d6ecb68bc313f64bdf2242e320f3797ba834a2692` to `bae708085fd6b3bd8854d5cc8a912cebcf28c7cefcc770f66a2461269d275b59`. The user's revised oracle bytes and Oracle A were left unchanged.

## 2026-09-09 — Oracle B direct Domain selection

The user revised Oracle B to remove first-class Decomposition construction and select immutable Domains directly from the Lattice with `Full`, `EvenParity`, and `OddParity`. Fields and iteration spaces consume those Domains directly; the existing volume assertions, Full Field equivalence, incompatible Field assignment checks, cross-Domain indexing rejection, access modes, and Execution Contexts are preserved.

Revised ADR 0003 records the reason: the intermediate Decomposition supplied no required operation beyond Domain construction. Domain selection retains Lattice provenance and selection semantics, and repeated equivalent selection remains compatible under the agreed shared-Geometry-and-Layout-instance contract.

The freeze-manifest checksum changed from `029ea467c259341dfc38a8f0f7372c7ab812c736c0122a913bf9300f4c2e29a1` to `79cfe99d94f3686a84bd4a2d6ecb68bc313f64bdf2242e320f3797ba834a2692`. The manifest records the user's revised file byte-for-byte; Oracle A is unchanged. Implementation and conformance tests still require migration to this contract.

## 2026-09-08 — Oracle A descriptive header comment

The user added a one-line comment at the top of the accepted Oracle A naming
it as the first-pass oracle establishing basic semantics, spaces, and
execution contexts.

This is a comment-only change. The oracle's source is otherwise byte-identical
to the previously frozen text: stripping the comment and the blank line that
follows it reproduces the previous checksum exactly. No construct, numerical
operation, access mode, iteration space, or execution placement is affected,
and no ADR is required.

The freeze-manifest checksum changed from `11407b5c294747da4b38df8c380678da1bd588e9b9a5e8b670262834959bc409` to `34320efb23ffba9479bd17a35b6a61adfe4680f482c50a4f8daff50f0889d09a`.

## 2026-09-08 — Oracle B initial freeze

The user approved the initial Oracle B contract for Lattice Decompositions and Field Domains. A Lattice produces a first-class Decomposition, each Decomposition produces immutable provenance-carrying Domains, and Fields and iteration spaces are constructed from those Domains. The Full Decomposition is equivalent to direct Lattice use; Fields on different non-equivalent Decompositions or Domains reject direct assignment, and Site Indices reject cross-Domain access.

Oracle B retains the established Execution Context and Field View requirements and names `EvenOdd`, `Even`, and `Odd` as the first concrete decomposition semantics. Its initial freeze-manifest checksum is `029ea467c259341dfc38a8f0f7372c7ab812c736c0122a913bf9300f4c2e29a1`.

## 2026-09-01 — Oracle A packed-site terminology

The user approved changing `simdSites` to `packedSites` in the accepted Oracle A. The old name described a common host execution mechanism, while the iteration space actually guarantees one layout-defined packed field value in every Execution Context, including accelerator execution.

This is a terminology correction only. A Packed Site represents the same group and produces the same packed value that the former SIMD Site represented; access modes, iteration extents, execution placement, and assertions are unchanged.

The freeze-manifest checksum changed from `506cad1e585dcf4230453b9fe6fc9354cc5105db5e3585a8e45efdc08cf6989f` to `7e13ee5e5d8161f9051af9b7af6a2659e774de1d26f8c41ddd9c1a7a2837807e`.

## 2026-09-01 — Oracle A explicit execution and iteration syntax

The user approved replacing `host:` and `accelerator:` with `within Host:` and `within Accelerator:`, replacing the separate site properties with `lattice.sites(Scalar)` and `lattice.sites(Packed)`, and naming the scalar index kind Scalar Site. The initial Whole-Field Assignments now appear inside `within Accelerator`, so placement is explicit everywhere rather than supplied by a special default.

This correction changes the language contract while preserving Oracle A's numerical operations, access modes, iteration extents, and selected execution placements. ADR 0002 records why Quark exposes execution context and site granularity as two orthogonal choices.

The freeze-manifest checksum changed from `7e13ee5e5d8161f9051af9b7af6a2659e774de1d26f8c41ddd9c1a7a2837807e` to `072a96eb1fdf6ef6f2bcefd13417f950043a76ec7eeff7a1d8718dd26699bf3e`.

## 2026-09-02 — Oracle A explicit field element type

The user approved making the Field element type explicitly `Complex[D]`, passing that type to `newScalarField`, and constructing the initial complex value with `newComplex`. The former bare `Complex` omitted its required static Precision parameter, and a result-only generic `newScalarField()` call could not determine the element type through ordinary Nim inference.

This correction makes the intended double precision and the Field-construction interface valid ordinary Nim. It does not change Oracle A's numerical operations, access modes, iteration extents, or execution placements, and the element type remains backend-neutral.

The freeze-manifest checksum changed from `072a96eb1fdf6ef6f2bcefd13417f950043a76ec7eeff7a1d8718dd26699bf3e` to `11407b5c294747da4b38df8c380678da1bd588e9b9a5e8b670262834959bc409`.
