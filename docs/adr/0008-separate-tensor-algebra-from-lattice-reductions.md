---
status: accepted
---

# Separate tensor algebra from lattice reductions

Tensor algebra is defined at a mathematical site and checked through small capabilities in `base/tensor.nim`, with Field Site Proxies exposing the corresponding readable algebra under their access qualifications. Milestone 1 requires trace, determinant, squared norms, infinity norms, vector Hermitian inner products (`v†w`), and Hermitian outer products (`vw†`). Applying a scalar-valued tensor operation pointwise to a Field produces a Numeric-valued Field on a conformable Lattice; a separate [lattice reduction](0007-scope-lattice-reductions-to-execution-contexts.md) combines sites. Pointwise Field semantics permit native expression evaluation without requiring intermediate Field allocation or a portable expression-tree representation.

For Real/Complex leaves, squared vector norms are `sum_i |v_i|²`, and squared matrix norms are `sum_i,j |M_ij|² = trace(M†M)`, recursively over supported tensor components. These are the squared Euclidean and Frobenius definitions shared by QEX and Grid. Vector inner products conjugate the first operand; outer products conjugate the second and return the corresponding matrix structure. Full trace contracts all supported matrix index spaces to a Numeric result; partial traces require separate names because they can retain tensor structure. The [native research](../research/grid-qex-reductions.md) supports these distinctions.

Conformance must check result shape, Spin identity where applicable, numeric kind and precision, mixed operand pairs, chaining, view permissions, and Field Lattice association. Structure classification alone does not require readable arithmetic, and matching each operand independently does not prove that the pair supports an operation. Backend facilities supply the implementation under [ADR 0011](0011-require-zero-abstraction-overhead.md).

The public operator spellings, infinity-norm definition, Integer norm/result rules, and supported nested determinant interpretation remain to be settled before Milestone 1 closes. A determinant of matrix-valued blocks cannot be inferred by recursively taking scalar determinants; specify the intended full operator and test native support. Adjoint, conjugation, and transpose are accompanying capabilities to scope explicitly. Native numerical acceptance must include complex conjugation-sensitive inner/outer products, singular matrices, and nonsingular matrices with a zero leading pivot. Unsupported native cases must be resolved or rejected explicitly while preserving the mathematical contract.
