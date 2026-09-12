---
status: accepted
---

# Parameterize Site kind statically

Use one Site Index family, `Site[L; K: static IterationSpace]`, with Scalar/Packed kind selected by the iteration space. `lattice.sites(Scalar)` yields `Site[L, Scalar]` and `lattice.sites(Packed)` yields `Site[L, Packed]`; these remain distinct compile-time types, preserving kind-dependent Field access without duplicated object declarations or a runtime kind discriminator. Host/Accelerator placement remains a separate property of the Execution Context, as established in [ADR 0002](0002-make-execution-and-site-selection-explicit.md).

The unified family retains Lattice type and instance provenance and rejects incompatible access as before. `ScalarSite[L]` and `PackedSite[L]` may remain aliases to preserve frozen oracle assertions and existing callers. The static parameter must erase under [ADR 0011](0011-require-zero-abstraction-overhead.md); unifying the declaration alone does not prove that all provenance or access machinery has zero overhead. Milestone 1 must migrate the iterator, Field conformance, adapters, and fixtures, preserving positive access and compile-time kind rejection. This is an accepted representation decision, not a claim that the current two object declarations have already been replaced.
