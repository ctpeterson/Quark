---
status: accepted
---

# Scope lattice reductions to Execution Contexts

Lattice reductions require an explicit `within Host` or `within Accelerator` context and explicit Site Granularity, because local computation, packing, synchronization, and communication affect performance and generated code. A reduction owns its parallel accumulation and combination through native backend facilities; the portable interface states the contribution and required result rather than exposing a shared accumulator updated by an ordinary Parallel Site Loop. Tensor operations within a site remain distinct from combining values across lattice sites, so summing tensor-valued contributions need not contract tensor indices.

Readable Views retain their access mode, lifetime, and Lattice provenance. Packed traversal must combine each selected scalar site's contribution exactly once, independently of tensor shape. The adapter must preserve the requested execution placement even when a backend convenience routine selects placement from build flags. Storage, thread/device reduction, lane folding, synchronization, and communicator operations remain backend responsibilities, subject to [zero abstraction overhead](0011-require-zero-abstraction-overhead.md).

Milestone 1 must still settle the reduction spelling, rank-local versus communicator-wide participation and defaults, accumulation/result precision, empty-domain behavior, and supported combiners. The [syntax candidates](../notes/reduction-interface.md) are proposals; this ADR does not accept `reduce(Sum)` or any other spelling. Completed results must have an explicit ownership and synchronization contract, and global reductions must specify collective participation. Freeze the accepted examples before Milestone 2 native implementation and verify both numerical results and required lowering. The [QEX/Grid research](../research/grid-qex-reductions.md) records why direct name-for-name mapping of native reductions is insufficient.
