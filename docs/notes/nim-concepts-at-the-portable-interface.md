# Exploratory note: Nim concepts at the portable interface

Date: 2026-09-07

Status: exploratory. This note records a direction Quark intends to investigate. The Lattice and numeric experiments described below are implemented, but broader adoption is not an accepted architectural decision and does not change the frozen Oracle A.

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

The current QEX and Grid types are temporary Milestone 1 conformance scaffolds. They prove that distinct adapter-owned types can satisfy the portable interfaces, but their storage and construction are not proposed native backend realizations. They are expected to be replaced or reshaped around the actual QEX and Grid lattice and layout types.

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

`ComplexNumber[P]` exposes its associated Real type through `realType` and requires its `re` and `im` projections to have that type. This lets portable Field operations preserve Precision without importing a backend or naming its concrete Real type.

## Likely next use: Field View capabilities

Field Views are the strongest candidate for the next experiment. A call such as `field.view(WriteDiscard)` could return a concrete adapter type carrying Field View Access Mode, Execution Context, and Lattice provenance as static parameters. The portable `FieldView[T]` concept would accept that concrete type while mode-specific overloads determine which operations compile.

Candidate capability concepts include readable, writable, and read-write site expressions. They should preserve these distinctions:

- `Read` permits reading and expressions but rejects assignment;
- `WriteDiscard` permits assignment but rejects reads and read-modify-write operations; and
- `ReadWrite` permits both.

The concept should describe the common interface; the concrete view and site-expression types should enforce the distinctions.

## Known limits and guardrails

- Concepts are not concrete storage types. With Nim 2.2.8, a direct variable annotation can retain its matched concrete type, but `seq[SomeConcept]` is invalid. Because Oracle A contains `seq[Field[Complex[D]]]`, `Field[T]` cannot simply become a concept. It needs a concrete selected type, a nominal facade, or another design that preserves homogeneous storage.
- A concept cannot serve as Oracle A's nested `Complex[D]` Field element type. The selected adapter therefore exports concrete numeric family types while portable concepts classify them and constrain generic operations.
- Structural matching can accept a type accidentally. Internal witness operations or other nominal anchors may be appropriate where merely sharing method names is too weak.
- Concept conformance proves that the required Geometry and Partition values and constructor expressions exist with the expected types. It does not prove that the stored Geometries are the results of applying the stored Partitions; constructors and focused semantic tests must enforce that value relationship.
- Identity-bearing values such as Fields and Site Indices should remain nominal where the governing invariants require provenance.
- The adapter interface should be split into small capability concepts only when operations genuinely vary independently. A large `Backend` concept would recreate the entire adapter implementation as a shallow interface.
- Concept diagnostics occur during matching and overload resolution. Add explicit compile-time conformance assertions and focused negative tests rather than relying on an eventual error deep inside Oracle compilation.

## Before expanding the experiment

For each candidate type, identify which facts are structural capabilities and which are Quark-owned semantic identities. Expand concept use only when the resulting interface stays smaller than the adapter machinery it hides. The next experiment is complete only when its positive and negative compile-time tests demonstrate the intended capability distinction and Oracle A remains unchanged.
