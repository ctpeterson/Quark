# Frozen oracle changes

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
