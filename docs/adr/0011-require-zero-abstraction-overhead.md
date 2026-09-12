---
status: accepted
---

# Require zero abstraction overhead

Zero abstraction overhead is a central design constraint of Quark. For supported optimized builds, expressing a program through Quark must add no runtime work or storage compared with an idiomatic direct-backend implementation of the same program with the same semantics, layout, precision, placement, and toolchain settings. Portability must preserve native performance: this is an acceptance requirement for interfaces and adapters, not an optional optimization after functionality is complete.

Static mathematical descriptions, capability checks, Site kind, access mode, and execution selection must erase. Quark must introduce no extra dynamic dispatch, allocation, reference-count traffic, data copies, tensor repacking, host/device transfers, synchronization, kernel launches, or communicator collectives. Backend work required by the requested operation and its semantics belongs in both sides of the comparison; unrelated inefficiencies in a chosen reference implementation cannot be used to justify Quark overhead. No portable feature may silently fall back to a more expensive representation or execution strategy and still claim conformance.

Lifetime, access-mode, and provenance guarantees remain in force, including [ADR 0006](0006-bind-view-access-to-lexical-scopes.md). Prove checks statically or hoist them to a valid scope/view/loop boundary wherever possible; any remaining runtime validation must be accounted for against a native implementation preserving the same guarantees. Moving extra work outside a kernel does not by itself satisfy the policy. If the contract and zero-overhead lowering cannot both be demonstrated, record the operation as incomplete or explicitly unsupported and resolve the design conflict; silently dropping checks or weakening semantics in optimized builds is not a solution.

For each native capability accepted in Milestone 2, retain a direct-backend reference and inspect optimized generated code for equivalent loop work, memory operations, allocations, transfers, and kernel/collective counts. Include host and accelerator lowering for both adapters where the capability is supported, with code inspection even when accelerator hardware is unavailable. Representative benchmarks supplement this evidence; timing noise, successful concept matching, or wrapper inlining alone cannot establish zero overhead. Pin the relevant backend, toolchain, and build configuration so regressions are reproducible.

Milestone 1 must select interfaces permitting this lowering and define the comparisons required for their acceptance. Its current metadata, view-lease, and provenance scaffolds establish contracts and are not evidence of native performance. Milestone 2 must demonstrate the policy alongside numerical and generated-code acceptance at each step; later regression infrastructure retains those checks. No milestone or adapter is declared compliant merely because this ADR exists.
