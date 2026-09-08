# Quark

The domain language for Quark, an experimental programming language for lattice field theory.

## Language

**Capability Concept**:
A small structural contract for one independently useful behavior that portable Quark code may require from adapter-owned types. It describes what a value can participate in rather than what category the value represents, without prescribing its concrete representation or semantic identity.
_Avoid_: Type classification, backend base class, monolithic backend interface

**Precision**:
The portable storage width of a numeric value: Half Precision (`H`) is 16 bits, Single Precision (`S`) is 32 bits, and Double Precision (`D`) is 64 bits. A backend may explicitly reject a Precision it cannot represent faithfully.
_Avoid_: Backend scalar type, arithmetic mode

**Numeric Kind**:
The portable mathematical category of a numeric value: Integer, Real, or Complex. Numeric Kind does not prescribe its backend representation or expression machinery.
_Avoid_: Precision, Field site type, backend scalar type

**Closed Numeric Arithmetic**:
Arithmetic whose result remains a numeric value of the same Numeric Kind and Precision as its operands. Closure is semantic and does not require the result to have the same concrete backend type.
_Avoid_: Concrete-type closure, eager evaluation

**Numeric Promotion**:
The portable result classification of mixed numeric arithmetic. The wider Precision wins, while Complex dominates Real and Real dominates Integer.
_Avoid_: Operator precedence, backend-selected coercion

**Lattice**:
A finite site space that owns its Geometry and a resolved Layout and from which Decompositions are derived. Execution Context determines where operations execute; a Lattice does not own Fields.
_Avoid_: Field container, lattice field, Decomposition

**Geometry**:
A finite logical index space with an extent in each direction. A Geometry may describe the complete Lattice or the result of applying a Partition.
_Avoid_: Partition, Layout, execution geometry

**Partition**:
A rule that splits a source Geometry into indexed parts, each having a resulting Geometry.
_Avoid_: Geometry, Site Domain, execution schedule

**Layout**:
The resolved application of a Rank Partition to the Lattice Geometry and a Packed Partition to the resulting Rank Geometry, together with Linearization into backend storage positions.
_Avoid_: Geometry, execution schedule

**Rank Partition**:
A Partition that splits the Lattice Geometry among the ranks in its communicator. Applying it for a rank produces that rank's Rank Geometry.
_Avoid_: Rank Geometry, Rank Decomposition, processor grid, thread chunk

**Rank Geometry**:
The Geometry produced by applying the Rank Partition for one rank; its sites are the Scalar Sites owned by that rank.
_Avoid_: Rank Partition, Lattice Geometry

**Packed Partition**:
A Partition that splits a Rank Geometry into layout-packed groups. Applying it produces the Packed Geometry.
_Avoid_: Packed Geometry, Packing, accelerator thread layout

**Packed Geometry**:
The Geometry produced by applying the Packed Partition; each of its sites identifies one Packed Site.
_Avoid_: Packed Partition, Rank Geometry

**Linearization**:
The part of a Layout that maps Scalar Sites, Packed Sites, and lanes to backend storage positions.
_Avoid_: Logical coordinate, Rank Decomposition

**Decomposition**:
A Lattice-associated rule that assigns every logical site to exactly one named Decomposition Domain. It preserves the source Lattice's provenance while allowing each Domain its own site organization.
_Avoid_: Partition, derived Lattice, iteration filter

**Decomposition Domain**:
One immutable, named subset produced by a Decomposition. It carries its source Lattice and Decomposition provenance and may define both a Field's support and an iteration space.
_Avoid_: Geometry, global parity label, mutable Field tag

**Full Decomposition**:
The identity Decomposition whose sole Domain contains the complete Lattice. Constructing a Field on that Domain is equivalent to constructing it directly from the Lattice.
_Avoid_: Site filter, copied Lattice

**Even-Odd Decomposition**:
A two-Domain Decomposition that assigns sites by lattice-site parity. `Even` and `Odd` identify Domains only together with their originating Lattice and Decomposition.
_Avoid_: Red-black Grid, checkerboard storage layout, global parity

**Field**:
A collection with one value of a specified site type at every site in its immutable Field Domain. A Field is associated with, but distinct from, the Lattice that established that Domain.
_Avoid_: Lattice, lattice object, mutable Domain tag

**Field Domain**:
The immutable site set over which a Field is defined: either the complete Lattice or one Decomposition Domain. It determines valid Site Indices and the coverage of Whole-Field Assignment.
_Avoid_: Iteration filter, mutable checkerboard flag

**Whole-Field Assignment**:
An assignment that writes a value to every site in a Field's Domain. Its enclosing Execution Context determines where it executes.
_Avoid_: Field View assignment, Site assignment, backend-selected placement

**Field View**:
A scoped, access-qualified handle to a Field. It preserves the Field's Lattice and site-value semantics while declaring how the Field may be accessed during the scope.
_Avoid_: Field copy, independent Field

**Field View Access Mode**:
The permission and data-preservation contract attached to a Field View. Every Field View has exactly one mode: Read, ReadWrite, or WriteDiscard.
_Avoid_: View hint, inferred access

**Read**:
A Field View Access Mode that makes existing values available but forbids modification through the view.
_Avoid_: ReadOnly

**ReadWrite**:
A Field View Access Mode that preserves existing values and permits any part of the viewed region to be modified.
_Avoid_: Write

**WriteDiscard**:
A Field View Access Mode that makes existing values unavailable and requires every element of the viewed region to be assigned before the view closes.
_Avoid_: WriteOnly, Write

**Site Index**:
A typed reference yielded by one Domain's iteration space and valid only for Fields associated with that Lattice and Domain. Its kind determines what kind of site value that access produces.
_Avoid_: Raw integer index, universal site number

**Scalar Site**:
A Site Index for one site in the current rank's Rank Geometry. Indexing a Field with a Scalar Site produces one scalar site value.
_Avoid_: Local Site, scalar site number

**Packed Site**:
A Site Index for one site in the Packed Geometry, representing one layout-defined group of Scalar Sites. Indexing a Field with a Packed Site produces the group's packed site value, independent of Execution Context.
_Avoid_: SIMD Site, packed site number

**Site Granularity**:
An explicit choice of Scalar or Packed that selects which Site Index kind a Lattice iteration space yields.
_Avoid_: Packing hint, backend vector width

**Execution Context**:
A required lexical scope selecting where its Whole-Field Assignments, Field Views, and Parallel Site Loops execute. Quark defines Host and Accelerator Execution Contexts; the selected backend supplies their concrete assignment, access, and loop constructs.
_Avoid_: Optimization hint, platform detection

**Host Execution Context**:
An Execution Context requiring host execution for Whole-Field Assignments, host-accessible Field Views, and the backend's host parallel loop.
_Avoid_: Accelerator context, serial context

**Accelerator Execution Context**:
An Execution Context requiring accelerator execution for Whole-Field Assignments, accelerator-accessible Field Views, and the backend's accelerator parallel loop. A CPU-only backend may realize that accelerator execution with host threads.
_Avoid_: GPU-only context, host context

**Parallel Site Loop**:
A site loop that must use the selected backend's native parallel loop construct for its enclosing Execution Context. It is an explicit lowering requirement, not permission or a hint to parallelize.
_Avoid_: Parallelization hint, ordinary serial loop
