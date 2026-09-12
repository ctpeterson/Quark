---
status: accepted
---

# Represent site selections as Lattices with immutable Domain kinds

A directly constructed Lattice has kind Full; `lattice.newSublattice(EvenParity)` and `lattice.newSublattice(OddParity)` derive other Lattices with immutable selection kinds and retained source association. The `Lattice` concept requires the common geometry, layout, and conformability operations, while only Full requires the `newLattice` constructors and parity selectors returning Lattices of the requested kinds; derived kinds do not require sibling selection, allowing distinct concrete types without cyclic selection requirements. Domain remains the name for site selection rather than a separate public concept or object, so Fields and iteration consume the same Lattice interface.

Revised 2026-09-09 with the user-approved Oracle B: the previous first-class Decomposition only mediated Domain construction, while the required operations consume individual Domains. Removing that intermediate public object preserves immutable Field support and cross-Domain rejection while leaving shared construction and storage machinery behind adapters. A first-class family of Domains can be reconsidered when portable operations need family enumeration, ownership queries, or relationships between parts; selecting a Domain alone does not require a public exhaustive, disjoint decomposition.

The subsequent user revision annotates the parity selections as Lattices and uses the directly constructed Full Lattice for Field construction. Conformability compares independently classified concrete types: differing kinds return false, while matching kinds require shared Geometry and resolved Layout instances. A same-type predicate in the concept establishes the minimum operation; adapter pair checks establish cross-type availability, and runtime conformability does not replace compile-time rejection of incompatible Field assignments or Site Indices.
