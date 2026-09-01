# Frozen oracle changes

## 2026-09-01 — Oracle A packed-site terminology

The user approved changing `simdSites` to `packedSites` in the accepted Oracle A. The old name described a common host execution mechanism, while the iteration space actually guarantees one layout-defined packed field value in every Execution Context, including accelerator execution.

This is a terminology correction only. A Packed Site represents the same group and produces the same packed value that the former SIMD Site represented; access modes, iteration extents, execution placement, and assertions are unchanged.

The freeze-manifest checksum changed from `506cad1e585dcf4230453b9fe6fc9354cc5105db5e3585a8e45efdc08cf6989f` to `7e13ee5e5d8161f9051af9b7af6a2659e774de1d26f8c41ddd9c1a7a2837807e`.

## 2026-09-01 — Oracle A explicit execution and iteration syntax

The user approved replacing `host:` and `accelerator:` with `within Host:` and `within Accelerator:`, replacing the separate site properties with `lattice.sites(Scalar)` and `lattice.sites(Packed)`, and naming the scalar index kind Scalar Site. The initial Whole-Field Assignments now appear inside `within Accelerator`, so placement is explicit everywhere rather than supplied by a special default.

This correction changes the language contract while preserving Oracle A's numerical operations, access modes, iteration extents, and selected execution placements. ADR 0002 records why Quark exposes execution context and site granularity as two orthogonal choices.

The freeze-manifest checksum changed from `7e13ee5e5d8161f9051af9b7af6a2659e774de1d26f8c41ddd9c1a7a2837807e` to `072a96eb1fdf6ef6f2bcefd13417f950043a76ec7eeff7a1d8718dd26699bf3e`.
