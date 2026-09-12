# Quark

A natural domain-specific language for high-performance lattice field theory workloads.

Quark expresses portable lattice programs in ordinary Nim while QEX and Grid supply native storage and execution. **Zero abstraction overhead is a central design constraint:** Quark must add no runtime work or storage compared with an equivalent direct-backend program preserving the same semantics. Explicit layout, access, and execution choices keep that performance intent inspectable.

The [zero-overhead decision](docs/adr/0011-require-zero-abstraction-overhead.md) defines the required evidence. This is a design and acceptance requirement; the current Milestone 1 conformance scaffolds do not establish native performance. See the [roadmap](ROADMAP.md) for implementation status and [development instructions](AGENTS.md) for the governing invariants.
