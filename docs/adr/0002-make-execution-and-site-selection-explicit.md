---
status: accepted
---

# Make execution context and site granularity explicit

Quark establishes every placement-sensitive operation inside `within Host` or `within Accelerator` and selects iteration through `lattice.sites(Scalar)` or `lattice.sites(Packed)`; `within` affects Quark Whole-Field Assignments, Field Views, and Parallel Site Loops while ordinary Nim retains its usual semantics. This replaces separate context macros, separate iteration properties, and the implicit Accelerator default with two small, orthogonal choices whose lowering remains visible to both backend adapters.
