# Session checkpoint: Lattice seam to Field design

Date: 2026-09-09

Purpose: historical checkpoint from the user's pause for other work. This is not an ADR or approval of its proposals.

Scope correction, 2026-09-11: use [ROADMAP.md — Milestone 1](../../ROADMAP.md#milestone-1--portable-interface-and-backend-seam) for current work. The proposed early native experiment below is superseded; this checkpoint does not authorize moving backend integration into Milestone 1.

## Resume here

The active milestone is **Milestone 1 — Portable interface and backend seam**. Lattice construction, selection, and conformability have a tested scaffold. We have moved into discussing Field, FieldSite, Tensor, and expression lowering. At the time of this checkpoint, an early native experiment was proposed but not accepted as a milestone requirement. Current work follows the roadmap's contract and conformance scope.

Start with repository status and relevant diffs, then read `CONTEXT.md`, `ROADMAP.md`, ADRs 0001–0003, both oracles, and `docs/notes/nim-concepts-at-the-portable-interface.md`. Preserve the existing working tree: it contains substantial user and earlier-session changes, including independent build-system work and untracked files. No commit was made for this checkpoint.

## Settled Lattice direction and implementation

- There is no separate public Domain or Decomposition object/concept. A Lattice carries an immutable, compile-time `DomainKind`: `Full`, `EvenParity`, or `OddParity`. `DecompositionKind` is derived classification.
- `newLattice` constructs Full. `domain(EvenParity)` and `domain(OddParity)` derive concrete types satisfying Lattice.
- Conformability requires the same Domain kind and the same Geometry and resolved Layout instances. Equal geometry or equal layout values alone do not suffice. Copies and identity-preserving Full selection are conformable.
- The Lattice concept requires constructors and parity selectors only for Full. Constructor expressions must return the matched concrete Full type; selector expressions must satisfy Lattice and carry the requested kind.
- Adapter conformance separately asserts that every supported constructor form returns kind Full. Merely asserting that its result satisfies Lattice would also admit a derived kind that skips the conditional constructor requirement.
- Same-type `conformable` belongs to the concept; adapter overloads use independent static kind parameters to support cross-kind comparisons. Different kinds return false. A runtime bool does not solve compile-time indexing or assignment rejection.
- Qualify `DomainKind.EvenParity` and `DomainKind.OddParity` in recursive concept checks; unqualified names caused Nim enum-name ambiguity in this experiment.
- Both backend Lattice implementations remain scaffolds. Parity selectors have the right return types but explicitly raise an unsupported-operation `ValueError`. Adapter integration with backend parity facilities and Oracle B acceptance remain follow-on work.

Relevant implementation: `src/quark/base/lattice.nim`, `src/quark/backend/{qex,grid}/*Lattice.nim`, `tests/latticeConcept.nim`, `tests/latticeConformability.nim`, and `tests/latticeInterface.nim`. The concept fixture includes negative modes for missing selectors and selectors returning the wrong kind.

User revisions to Oracle B were reflected in its freeze manifest and documentation. Do not change the frozen source to fit an implementation. Its existing trailing whitespace on line 24 was deliberately left untouched.

## Field decisions and user priorities

- Field needs a concrete family, notably because Oracle A stores `seq[Field[Complex[D]]]`. Concepts can constrain concrete types and expressions, following the numeric interface approach.
- The user agreed to shared Field ownership. Ordinary handle copies alias storage; `:=` writes the destination's existing storage. This is recorded under Field Handle in `CONTEXT.md` and in `CHANGELOG.md`.
- The user favours reference types for ergonomics but is open to alternatives, including for FieldSite. A Nim `ref object` representation has **not** been settled.
- The user wants syntax and conformance in Milestone 1. Storage and execution are backend responsibilities; subsequent adapter milestones connect Quark to those facilities.
- Interoperability with native Grid FermionOperator classes and QEX operators is essential. A portable Tensor representation must not prevent use of their canonical types or introduce hidden representation conversions.
- The user raised whether this is the right stage for an IR, and whether repeatedly accessing wrapped backend types inside a parallel loop would introduce overhead.

## Open proposals from the discussion

1. Field is an owning shared handle. FieldSite is a concrete, scoped access handle through a FieldView. A lightweight value proxy can provide reference behaviour without allocating a Nim ref object per site. Copying that proxy would still refer to the original destination. Lifetime enforcement remains to be designed.
2. Separate the mathematical site value type from its access handle. A readable matrix site could satisfy Tensor capabilities without sharing the concrete type of an owned matrix value. WriteDiscard can expose type/shape metadata while rejecting reads and read-modify-write operations.
3. Arithmetic results should be native values or expressions as appropriate; they need not be another assignable FieldSite. The current scaffold's arithmetic signatures are not a settled expression model.
4. Develop enough Tensor classification alongside Field to preserve shape and spin/colour structure, with concrete native representations selected by adapters. Do not assume a flat tensor with matching dimensions is accepted by native physics operators.
5. Concepts describe supported operations; an IR describes computation and lowering. More concepts cannot establish fusion, lifetime correctness, or absence of runtime overhead.
6. Start from Nim's syntax tree and a small set of Quark operations. A private expression representation may help with whole-Field assignment/fusion and, if needed, deferred site loads or projections. No separate general-purpose language, parser, type system, or IR has been accepted. Preserve ordinary Nim helper procedures and control flow inside loops, consistent with ADR 0001.

## Superseded experiment proposal

An earlier discussion proposed bringing a native view and site-access probe forward to inform the Field interface. The user has clarified that Milestone 1 is syntax and conformance work. That probe is not the next step or a prerequisite for Field, View, or Site Proxy design; any backend integration follows the later adapter milestones in `ROADMAP.md`.

## Evidence gathered

- Grid has compile-time `iVector<vtype, N>` and square `iMatrix<vtype, N>` families, composed into nested tensors: [Tensor_class.h](https://github.com/paboyle/Grid/blob/develop/Grid/tensors/Tensor_class.h).
- Grid's QCD aliases preserve nested spin/colour structure. FermionOperator consumes its implementation's concrete FermionField: [QCD.h](https://github.com/paboyle/Grid/blob/develop/Grid/qcd/QCD.h), [FermionOperator.h](https://github.com/paboyle/Grid/blob/develop/Grid/qcd/action/fermion/FermionOperator.h).
- Local Grid source inspected at `/home/curtyp/Software/05-19-2026-Grid-HISQ/Grid/`. `lattice/Lattice_view.h` has accelerator-inline indexing returning native references and separate ViewOpen/ViewClose operations.
- Local QEX source inspected at `/home/curtyp/Software/scratch/qex/src/`. `field/fieldET.nim` defines Field as a ref to FieldObj. `physics/qcdTypes.nim` uses Color-wrapped MatrixArray types and Spin-wrapped vectors of colour vectors for Dirac fermions. `maths/matrixConcept.nim` supplies static-dimension MatrixArray and VectorArray types.
- Nim templates expand during compilation; importcpp patterns can express native C++ operations directly. Neither by itself proves optimized output is free of extra work: [Nim manual](https://nim-lang.org/docs/manual.html).

## Verification and working-tree state

The last full `nimble verify` after the Full-constructor checks passed; its temporary log is `/tmp/quark-full-constructor-verify.log`. This covered the oracle freeze check, build tests, Lattice concept fixtures including negative modes, and the adapter interface checks. It is not native Oracle A/B execution acceptance.

Since then, the Field discussion changed only the ownership documentation in `CONTEXT.md` and `CHANGELOG.md`; their whitespace checks passed. No Field, Tensor, or iteration implementation changes were made during that discussion. The full working-tree whitespace check previously reported the pre-existing Oracle B trailing whitespace. This checkpoint adds documentation only and does not claim a fresh full verification run.

Communication preference: give substantive explanations with concrete examples and distinguish tested facts from design proposals. The user previously found terse, vague responses unhelpful. Resume the design conversation from the IR/accessor question instead of treating every proposal here as an implementation instruction.
