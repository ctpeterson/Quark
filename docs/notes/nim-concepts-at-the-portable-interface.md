# Exploratory note: Nim concepts at the portable interface

Date: 2026-09-07

Status: exploratory. This note records a direction Quark intends to investigate. The Lattice and numeric experiments described below are implemented, but broader adoption is not an accepted architectural decision and does not change the frozen Oracle A.

Milestone scope is governed by [ROADMAP.md — Milestone 1](../../ROADMAP.md#milestone-1--portable-interface-and-backend-seam). Use these experiments to refine contracts and conformance within that scope.

The accepted [tensor-description decision](../adr/0009-separate-tensor-descriptions-from-native-values.md) supersedes this note's earlier expectation of public adapter-owned tensor value families: `Vector`, `Matrix`, and `Spin` describe mathematical site types, while native storage/access/results remain adapter-owned. The [unified Site decision](../adr/0010-parameterize-site-kind-statically.md) and [zero-abstraction-overhead constraint](../adr/0011-require-zero-abstraction-overhead.md) also govern the pending migration. Implementation descriptions below record the existing scaffolds, not completion of those decisions.

## The idea

Nim concepts may provide a useful interface at the seam between Quark's portable semantics and its backend adapters. A portable annotation can name the required behavior while the selected adapter supplies a concrete type with its own representation and lowering machinery. Matching is compile-time and retains the concrete type, so this need not introduce runtime dispatch or type erasure.

Concepts are promising for:

- stating the operations and associated types required from backend-owned Lattices, Field Views, and site expressions;
- giving QEX and Grid unrelated concrete representations behind one small portable interface;
- constraining generic arithmetic and assignment to meaningful read and write capabilities; and
- producing focused compile-time adapter-conformance checks.

A concept proves that required expressions type-check. It does not prove Quark semantics such as correct synchronization, view closing, provenance, or use of a required backend loop construct. Focused negative, numerical, and generated-code tests remain the authority for those properties.

## First experiment: lattice geometry and partitioning

The first experiment makes `Geometry`, `Partition`, and `Lattice` concepts. Geometry describes a finite index space. Partition describes how a source Geometry is split. Lattice directly exposes the resolved chain of Rank Partition to Rank Geometry and Packed Partition to Packed Geometry; Layout remains the domain name for that resolution and its backend linearization rather than a separate portable concept. `BasicLattice` and its related types are only smoke-test fixtures demonstrating structural matching; production construction belongs to the selected adapter.

The current QEX and Grid types are Milestone 1 conformance scaffolds. They demonstrate that distinct adapter-owned types can satisfy the portable interfaces. Later adapter integration uses the actual QEX and Grid lattice and layout facilities.

Portable source can configure the partition chain without naming those scaffolds:

```nim
let geometry: Geometry = newGeometry([8, 8, 8, 16])
let rankPartition: Partition = newPartition([2, 1, 1, 2])
let packedPartition: Partition = newPartition([1, 2, 2, 1])
let lattice: Lattice = newLattice(
  geometry,
  rankPartition,
  packedPartition
)
```

The frozen oracle's shorter construction remains valid and delegates both partitions to the selected backend. The temporary scaffolds currently infer unit partitions:

```nim
let lattice: Lattice = newLattice([8, 8, 8, 16])
```

Either partition may be specified by name while the selected backend infers the other:

```nim
let rankConfigured = newLattice(
  [8, 8, 8, 16],
  rankPartition = [2, 1, 1, 2]
)
let packingConfigured = newLattice(
  [8, 8, 8, 16],
  packedPartition = [1, 2, 2, 1]
)
```

This is a deliberately small step toward Milestone 1's portable-interface and backend-seam criterion. It is successful while all of the following remain observable:

- Oracle A compiles unchanged;
- the concrete implementation remains available to Nim after concept matching;
- no runtime interface object or backend type appears in portable source; and
- QEX and Grid geometry, partition, and lattice scaffolds satisfy the same interfaces without sharing base objects or exposing their names through `import quark`.

The initial adapters implement regular partitions with one positive factor per Geometry direction. Construction validates non-empty positive values, integer products, equal dimensionality, and exact divisibility. Unsupported irregular or padded partitions reject explicitly; the Partition interface leaves room for later backend implementations that can represent them faithfully.

Geometry and Partition expose their directional values through array indexing. For a Geometry, an index selects an extent; for a Partition, it selects a factor.

Lattice exposes `rankPartition`, `rankGeometry`, `packedPartition`, and `packedGeometry` directly. It also exposes `dimensions`; portable `volume` and `directions` derive from the Lattice Geometry and dimension count. An adapter may keep a concrete Layout value behind those accessors, but portable callers do not need a separate Layout interface. Linearization remains part of the domain meaning of Layout but is not yet observable through the Milestone 1 interface.

This experiment does not yet solve Site Index provenance. A concept describes behavior shared by types; it does not create a fresh nominal identity for each Lattice value. Provenance still needs a deliberate representation, likely involving phantom types, macro-generated identities, or compile-time checks at the indexing expression.

## Second experiment: numeric families

The numeric experiment separates portable classification from concrete storage. `Precision` and `NumericKind` are portable semantics. `IntegerNumber[P]`, `RealNumber[P]`, and `ComplexNumber[P]` concepts classify adapter-owned value types; the selected adapter supplies the concrete `Integer[P]`, `Real[P]`, and `Complex[P]` families, constructors, conversions, and scalar projections exported through `import quark`.

This split is necessary because Oracle A uses `Complex[D]` as the element type in `Field[Complex[D]]`. Nim 2.2.8 accepts a concept as a direct parameter annotation, but rejects a concept nested as the concrete type argument of another type. Consequently, the Oracle-facing family names must resolve to concrete selected-adapter types rather than concepts. Focused tests compile the same family names against QEX and Grid and assert that their concrete types satisfy the portable concepts.

Numeric classification and arithmetic capability are separate so generic code pays only for the interface it needs. `IntegerNumber[P]`, `RealNumber[P]`, and `ComplexNumber[P]` identify concrete values and expressions by portable Precision and Numeric Kind. `IntegerArithmetic[P]`, `RealArithmetic[P]`, and `ComplexArithmetic[P]` additionally require unary and same-Kind binary arithmetic to remain semantically closed. Integer arithmetic uses `div` and `mod`; Real and Complex arithmetic use `/`.

Semantic closure does not require concrete-type closure. A backend operation may return a proxy or lazy-expression type rather than another stored value directly, provided the result satisfies the corresponding numeric classification and remains usable in chained arithmetic. Adapter conformance and focused expression tests check that additional chainability without forcing eager materialization.

Mixed arithmetic follows portable Numeric Promotion. `promotedPrecision` selects the wider Precision (`H` to `S` to `D`), and `promotedKind` selects the dominant Numeric Kind (Integer to Real to Complex). Focused tests cover both operand orders, chained expressions, and the floating literals used by Oracle A. Nim's parser remains the sole authority for operator precedence and associativity.

Constructors remain part of adapter conformance rather than numeric classification or arithmetic concepts.

The compound classification is `Numeric[P]` (renamed from `Number[P]` on September 12). It accepts any of the three numeric families at `P` without requiring arithmetic. The individual family concepts retain their names.

`ComplexNumber[P]` exposes its associated Real type through `realType` and requires its `re` and `im` projections to have that type. This lets portable Field operations preserve Precision without importing a backend or naming its concrete Real type.

## Third experiment: Lattice kinds and conformability

Oracle B and revised ADR 0003 use Lattice for both directly constructed Full values and derived parity selections. Domain classification and conformability are part of `Lattice`; there is no separate Domain concept. `domain` is available at compile time, and the concept requires `newLattice` only for Full.

The reverse requirement is checked explicitly at adapter conformance: every supported `newLattice` form must return both a Lattice and kind Full. Checking only the result's Lattice conformance would also accept a parity type, which skips the conditional constructor branch. These checks cover inferred partitions, either explicit partition, both explicit partitions, and Geometry/Partition arguments.

Full also requires `newSublattice(EvenParity)` and `newSublattice(OddParity)` to return Lattices of the requested kinds. These requirements are inside the Full branch: derived kinds do not recursively require selection, and their concrete types may differ from Full. The concept uses qualified `Domain` values for selection expressions to avoid enum-name ambiguity during matching. Negative fixtures reject a Full implementation with missing selectors or with a selector returning the wrong kind, even when its result otherwise satisfies Lattice.

`conformable(lattice, lattice)` checks the predicate for a single matched concrete type. Each adapter's predicate accepts independent static kind parameters; different kinds return false, while matching kinds require shared Geometry and resolved Layout instances. Generic callers constrain their two types independently and resolve `conformable` for the pair. Pair checks supplement the concept because two types matching independently do not imply that a cross-type operation exists.

The temporary QEX and Grid scaffolds retain private shared Geometry and resolved Layout instances and preserve them through copies and Full selection. They expose typed parity selectors but explicitly raise `ValueError` until the adapters connect to backend parity facilities. Compiler fixtures exercise successful Full-to-parity derivation with distinct concrete types; these fixtures do not implement native site organization. Site Indices now retain their originating Lattice type and value: Field indexing rejects incompatible kinds during compilation and incompatible Geometry/Layout instances at runtime. Focused rejection tests exercise both layers; parity storage and full Oracle B acceptance remain Milestone 2 work.

## Fourth experiment: Field classification and constructor conformance

`FieldObject[T]` classifies an existing Field by its associated `siteType`, Lattice, and the availability of views carrying each requested access mode. It does not require construction or whole-Field arithmetic; readable site access must provide the algebra of its site type. Constructor conformance separately checks that `lattice.newField(T)` returns the advertised concrete `Field[T]` family with the requested site type and Lattice type; runtime tests check that the actual Lattice association is conformable to the supplied instance.

Both adapters provide temporary concrete shared reference handles with private Lattice associations. Default `Field[T]` names the Full-Lattice case needed by Oracle A's sequence; construction on a derived Lattice infers an additional concrete Lattice type parameter. Copies share a handle, and independent constructor calls create different handles on the same Lattice. These handles establish ownership and association contracts for this milestone.

`FieldViewObject[T]` checks the associated site type, Lattice, compile-time access mode, and indexing with Scalar Site and Packed Site values. The resulting `FieldSiteProxy[T, S]` must report the requested site type, index type, and the view's access mode. Mode equality is checked as well as mode classification: an adapter returning Read for every request rejects. Structural matching alone does not establish lifetime, WriteDiscard coverage, placement, or instance provenance. Adapter scope and indexing checks now enforce lifetime, explicit context, and provenance separately; WriteDiscard storage coverage remains part of native Field integration.

Each adapter supplies a concrete `FieldView[T, Mode, LatticeType]` object satisfying `FieldViewObject[T]`. The Lattice type defaults to Full, while `field.view(mode)` infers all three parameters. Oracle A now uses ordinary inferred declarations; explicit declarations can name `FieldView[T, Mode]`. A concrete `FieldView[T]` annotation cannot omit the required static mode parameter in Nim 2.2.8. The former delegating concept has been removed. Focused tests exercise inferred and explicitly annotated views for all three modes, preserve derived Lattice types, and reject mismatched annotations and runtime mode arguments.

Independent negative fixtures reject wrong site types, wrong index types, missing access, mismatched modes, and runtime-only modes. A structurally valid fixture with no matching constructor confirms that classification and construction remain separate. The portable Field module now contains only access modes and classification concepts. Shared syntax placeholders live internally in `backend/common/commonField.nim` while QEX and Grid own their Field handles, concrete Views, and constructors. These placeholders support Oracle A syntax checks and reject unimplemented Field operations explicitly at runtime.

## Deferred experiment: Field arithmetic and expressions

The initial whole-Field expression experiment has been removed from the active implementation following the September 11 scope reduction. Its classification concepts, private operation-tagged nodes, evaluator, and expression-specific tests exceeded the chosen scope of Field classification and conformance.

Deferred Field arithmetic remains domain vocabulary in `CONTEXT.md`; its representation is unsettled. It is not a completed Milestone 1 capability. Oracle A currently needs scalar whole-Field initialization and arithmetic through indexed views. Focused tests retain its initialization syntax, explicit assignment context, access-mode rejections, and explicit errors for unimplemented storage operations.

Continue interface work through focused positive and negative conformance tests against the active milestone criteria. The earlier recommendation to require a native view/access/lowering probe before continuing this work is superseded by the milestone scope in the roadmap.

## Site Proxy algebra — agreed direction, 2026-09-12

`FieldSiteProxy[T, S]` exposes the algebra of `T`: numeric site types provide the corresponding Integer, Real, or Complex algebra; vector and matrix site types provide vector and matrix algebra. Selecting a numeric component of a vector or matrix exposes that component's numeric algebra. This is capability conformance, without requiring concrete type inheritance or making every arithmetic result another Field Site Proxy.

Access modes qualify these capabilities throughout: Read permits reading and arithmetic, ReadWrite additionally permits updates, and WriteDiscard permits assignment while rejecting operations that read existing values. Component access retains the parent access mode, scope, site provenance, and Scalar/Packed granularity. A component of a packed matrix represents the corresponding component across the packed sites; tensor indices do not select packing lanes.

The adapter selects concrete numeric representations appropriate to the Execution Context and Site Granularity. Numeric Kind, Precision, and the mathematical vector/tensor structure remain portable; a numeric component need not have the same concrete type as its mathematical site-type declaration. The current `FieldSiteProxy` concept checks the corresponding Integer, Real, or Complex arithmetic capability for readable numeric sites, using `T.precision` independently of the matched proxy type. Independent numeric fixtures reject missing arithmetic, wrong result kinds, and wrong precision.

For tensor site types, it checks vector or square-matrix algebra and preserves spin identity when the site type satisfies `SpinObject`, recursively requiring components to satisfy `FieldSiteProxy` with the declared mathematical component type, the same index type, and the same access mode. Tensor classification takes precedence over forwarded numeric metadata. WriteDiscard proxies retain structural conformance and component-handle selection without requiring reads. Unsupported site algebras reject concept matching. `tests/fieldTensorConcept.nim` checks nested tagged tensors through both direct proxies and complete Field/View conformance, including rejection of lost component modes, index types, shape, and spin identity. Ordinary tensors require no index-space metadata; only spin types expose the compile-time boolean `isSpin = true`. These structural checks do not establish instance provenance or scope enforcement.

Both adapter scaffolds preserve numeric kind, precision, and Scalar/Packed granularity through chained site arithmetic and complex projections; arithmetic results carry no assignment capability. These are compile-time contracts, with placeholder operations still rejecting execution explicitly.

`Spin[...]` is agreed to be a mathematical index-space tag around a vector or matrix, retaining its shape and component structure. The [Grid/QEX Spin research](../research/grid-qex-spin-representation.md) records the supporting evidence. A spin component can still be a colour vector; numeric algebra applies at the leaf. The expanded Oracle C now fixes `Vector[T, N]`, square `Matrix[T, N]`, and `Spin[T]`, including generic 3-component Spin examples and nested 4-spin/3-colour structures. Concrete adapter families remain pending. Spin-specific physics operations beyond that arithmetic still need their own contract.

## Known limits and guardrails

The [tensor interface and backend compatibility note](tensor-interface-and-backend-compatibility.md) records the canonical physics-type constraints and implemented `VectorObject[T, N]`, `MatrixObject[T, N]`, arithmetic, and `SpinObject[T]` contracts. Matrices are square in this first contract. Private compile-time generic helpers support recursive component checks within Nim's concept-matching depth limit; independent fixtures run against both adapters' numeric families.

- Concepts are not concrete storage types. With Nim 2.2.8, a direct variable annotation can retain its matched concrete type, but `seq[SomeConcept]` is invalid. Because Oracle A contains `seq[Field[Complex[D]]]`, `Field[T]` cannot simply become a concept. It needs a concrete selected type, a nominal facade, or another design that preserves homogeneous storage.
- A concept cannot serve as Oracle A's nested `Complex[D]` Field element type. The selected adapter therefore exports concrete numeric family types while portable concepts classify them and constrain generic operations.
- Structural matching can accept a type accidentally. Internal witness operations or other nominal anchors may be appropriate where merely sharing method names is too weak.
- Concept conformance proves that the required Geometry and Partition values and constructor expressions exist with the expected types. It does not prove that the stored Geometries are the results of applying the stored Partitions; constructors and focused semantic tests must enforce that value relationship.
- Identity-bearing values such as Fields and Site Indices should remain nominal where the governing invariants require provenance.
- The adapter interface should be split into small capability concepts only when operations genuinely vary independently. A large `Backend` concept would recreate the entire adapter implementation as a shallow interface.
- Concept diagnostics occur during matching and overload resolution. Add explicit compile-time conformance assertions and focused negative tests rather than relying on an eventual error deep inside Oracle compilation.

## Before expanding the experiment

For each candidate type, identify which facts are structural capabilities and which are Quark-owned semantic identities. Expand concept use only when the resulting interface stays smaller than the adapter machinery it hides. The next experiment is complete only when its positive and negative compile-time tests demonstrate the intended capability distinction and Oracle A remains unchanged.

## Milestone 1 scope and provenance closeout

Field classification checks view construction inside a compile-time Host context. View classification derives `ScalarSite[L]` and `PackedSite[L]` from its associated Lattice type and checks indexed expressions in that context, without executing resource acquisition. Positive and negative fixtures retain the distinction between structural matching and concrete adapter enforcement.

Concrete adapter views require an explicit Execution Context when opened and indexed. `within` establishes a new lexical scope and cleanup bound; the shared `base/execution.nim` machinery separates copyable access handles from exactly-once close ownership. Copies and Site Proxies reject use after closure, including after exception unwinding. Site Indices retain their source Lattice, with compile-time kind rejection and runtime instance conformability checks. See [Milestone 1 closeout](milestone-1-closeout.md) for tests, expansion inspection, and build evidence.
