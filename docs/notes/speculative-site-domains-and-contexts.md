# Speculative note: site domains and Quark contexts

Date: 2026-09-01

Status: speculative. This note records design ideas for later investigation. It does not change Quark's domain vocabulary, accepted decisions, roadmap, or frozen Oracle A.

## Current shape

Oracle A appears to exercise all lexical contexts needed for its present semantics:

```text
quark program/runtime lifetime
└── within Host | Accelerator          execution placement
    ├── field.view(access mode)         scoped access and coherence lease
    └── lattice.sites(site granularity) iteration index kind
        └── parallel for                backend-native scheduling
```

Only `quark` and `within` are contexts in the lexical sense. A Field View is a scoped lease, Site Granularity is an iteration-space selector, and `parallel for` is an explicit lowering requirement. Treating every scoped or selectable property as another context would blur otherwise independent concerns.

Separating consecutive `within Accelerator` blocks is semantically reasonable even when a single block could contain the same operations. Each block then describes one execution phase and bounds the lifetime of its Field Views. Source order between consecutive blocks should be preserved, but leaving a block need not imply a global accelerator synchronization or an eager host/device copy. A later incompatible view or operation should perform whatever ordering and synchronization correctness requires.

The last paragraph is a proposed interpretation, not yet a complete asynchronous execution contract. Before Quark exposes nonblocking work, events, streams, or overlapping contexts, it must define when work completes and how a view lease remains alive until completion.

## Possible missing axis: Site Domain

A future oracle may need to select a subset of a Lattice independently of both execution placement and site granularity. Possible examples include:

- all rank-local sites;
- even or odd checkerboard sites; and
- interior or boundary sites for communication overlap.

The tentative canonical term is **Site Domain**: the subset of a Lattice over which an iteration space ranges. One possible source shape is:

```nim
within Accelerator:
  parallel for n in lattice.sites(Packed, domain = Even):
    discard
```

This is intentionally only a syntax sketch. It should not be added to Oracle A merely to reserve the interface. A new oracle should introduce it when a concrete operation requires it.

Site Domain raises semantic questions that must be answered before acceptance:

- Is `All` implicit, or must every domain be named?
- Are `Even` and `Odd` intrinsic Lattice domains, backend-defined domains, or values constructed from a Lattice?
- Does a domain preserve stable Site Index provenance when it is composed or filtered?
- Must every backend support every domain, or may an adapter reject unsupported domains explicitly?
- Does `WriteDiscard` require complete assignment of the whole Field, or only of the Field View's declared domain? If the latter, the viewed region must become part of the lease contract.
- How do halo exchange and interior/boundary iteration state their ordering without turning communication into another Execution Context?

## Concerns that should remain elsewhere

The following concerns may affect lowering, but do not currently justify more lexical contexts:

- Halo exchange and off-rank access are communication operations with explicit completion behavior.
- Reductions are operations with a result and ordering contract.
- Precision and storage layout belong to Field or Lattice construction and types.
- Rank and communicator selection belong to the Lattice.
- Concrete device choice, streams, and host thread counts are adapter configuration until portable source needs to distinguish them semantically.
- Field construction outside `within` creates a logical Field; it does not itself select the authoritative host or accelerator copy.

This keeps the portable interface deep: Quark source exposes the few choices that affect program meaning or generated-code shape, while backend adapters own the machinery required to realize them.
