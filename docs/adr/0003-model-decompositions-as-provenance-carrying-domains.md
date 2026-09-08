---
status: accepted
---

# Model decompositions as provenance-carrying domains

A Lattice produces first-class Decompositions, and each Decomposition produces immutable Domains from which Fields and iteration spaces are constructed. Keeping a Domain's Lattice and Decomposition provenance in those values prevents mutable reinterpretation and accidental cross-Domain operations, while allowing adapters to hide representations such as Grid's derived red-black geometry; the Full Decomposition is the identity and remains equivalent to direct Lattice use.
