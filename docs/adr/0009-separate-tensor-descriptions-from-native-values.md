---
status: accepted
---

# Separate tensor descriptions from native values

`Vector[T, N]`, square `Matrix[T, N]`, and `Spin[T]` describe a Field's mathematical site type without prescribing a standalone tensor-storage representation. They remain valid Nim type arguments carrying static shape, component, and tag information; structural concepts classify them, while algebraic capabilities constrain concrete access and expression types. This preserves Oracle C's declarations without requiring a single runtime tensor representation to serve every layout and execution context.

An adapter resolves native Field storage from the description and the Lattice's resolved Layout when storage is allocated. A Field Site Proxy is selected using that description, the Site Index's Scalar/Packed kind, the enclosing Host/Accelerator Execution Context, and the View's access mode. Arithmetic results and tensor-valued reductions may use other concrete native value or expression types; they need not be assignable proxies or retain a borrow after producing an owning result. Representation must preserve native physics-operator compatibility and [zero abstraction overhead](0011-require-zero-abstraction-overhead.md).

The descriptions need no runtime instances, storage arrays, or dummy value arithmetic. The current scaffold's use of `default(siteType)` arithmetic must be replaced when implementing this separation; it is not a requirement on the descriptions. The public description types belong to the backend-neutral interface, while native representations and operations remain behind adapters. This decision does not turn `Numeric` or the existing numeric families into a new representation scheme, nor require a public standalone tensor-value API. The [type feasibility and consequences](../notes/tensor-interface-and-backend-compatibility.md#site-descriptions-and-concrete-access-types--september-12-follow-up) are documented; production types still require migration in Milestone 1.
