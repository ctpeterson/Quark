# Quark

The domain language for Quark, an experimental programming language for lattice field theory.

## Language

**Zero Abstraction Overhead**:
The requirement that a Quark program adds no runtime work or storage compared with an equivalent direct-backend program preserving the same semantics, layout, precision, and execution placement. It is a portability constraint, not a claim that all backends or machines run at identical speed.
_Avoid_: Best-effort optimization, negligible overhead, optional performance tuning

**Capability Concept**:
A small structural contract for one independently useful behavior that portable Quark code may require from adapter-owned types. It describes what a value can participate in rather than what category the value represents, without prescribing its concrete representation or semantic identity.
_Avoid_: Type classification, backend base class, monolithic backend interface

**Precision**:
The portable storage width of a numeric value: Half Precision (`H`) is 16 bits, Single Precision (`S`) is 32 bits, and Double Precision (`D`) is 64 bits. A backend may explicitly reject a Precision it cannot represent faithfully.
_Avoid_: Backend scalar type, arithmetic mode

**Numeric Kind**:
The portable mathematical category of a numeric value: Integer, Real, or Complex. Numeric Kind does not prescribe its backend representation or expression machinery.
_Avoid_: Precision, Field site type, backend scalar type

**Numeric**:
The compound capability `Numeric[P]` accepting Integer, Real, or Complex values at Precision `P`. It classifies adapter-owned values and expressions without prescribing their storage or requiring arithmetic.
_Avoid_: Number (former compound concept name), concrete numeric family

**Closed Numeric Arithmetic**:
Arithmetic whose result remains a numeric value of the same Numeric Kind and Precision as its operands. Closure is semantic and does not require the result to have the same concrete backend type.
_Avoid_: Concrete-type closure, eager evaluation

**Numeric Promotion**:
The portable result classification of mixed numeric arithmetic. The wider Precision wins, while Complex dominates Real and Real dominates Integer.
_Avoid_: Operator precedence, backend-selected coercion

**Spin**:
A mathematical index-space tag around a vector or matrix, identifying its indices as spin indices while retaining its shape and component structure. Components may themselves be vectors or matrices, so selecting a spin component need not produce a numeric value.
_Avoid_: Untagged vector dimension, Site Granularity, numeric representation

**Lattice**:
A finite site space with a Geometry, resolved Layout, and immutable Domain classification. Full Lattices are constructed directly; parity Lattices are derived from Full while preserving their source association, and Fields remain separate values.
_Avoid_: Field container, lattice field, Decomposition

**Lattice Conformability**:
The relationship between Lattices of the same Domain classification sharing precisely the same Geometry and resolved Layout instances, including rank partitioning, packing, and Linearization, with derived selections preserving their source association. Separate Lattice values may be conformable; equal geometric extents alone or differing Layouts do not establish conformability.
_Avoid_: Equal volume, equal dimensions, Lattice allocation identity

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

**Domain**:
The immutable logical site selection of a Lattice, defining its iteration space and the support of Fields constructed on it. A selected subset is itself a Lattice with its own site organization and retained source association.
_Avoid_: Decomposition Domain object, iteration filter, mutable Field tag

**Domain Classification**:
The classification of a Lattice's site selection: Full, Even Parity, or Odd Parity. It describes selection semantics without identifying the source Geometry or Layout instances.
_Avoid_: Provenance, mutable checkerboard flag

**Decomposition**:
The classification of the rule underlying a Domain classification: No Decomposition for Full, or Site Parity for Even Parity and Odd Parity. It describes the rule without introducing a separate Decomposition object.
_Avoid_: Decomposition object, Lattice identity

**Full Domain**:
The default complete site selection of a directly constructed Lattice, classified by `Full`. Selecting Full preserves the original Lattice's conformability.
_Avoid_: Site filter, copied Lattice

**Parity Domain**:
The site selection of a Lattice derived from Full by `EvenParity` or `OddParity`. The selection retains its source association; the two Parity Domains are disjoint and together cover the source Full Domain.
_Avoid_: Even-Odd Decomposition, red-black Grid, checkerboard storage layout, global parity

**Field**:
A collection with one value of a specified site type at every site in its immutable Field Domain. A Field is associated with, but distinct from, the Lattice that established that Domain.
_Avoid_: Lattice, lattice object, mutable Domain tag

**Site Value**:
The mathematical value associated with one Scalar Site of a Field, which may be numeric or tensor-valued. Its mathematical type is independent of Site Granularity: Packed Site access represents a layout-packed group of those values.
_Avoid_: Site Index, tensor component, packed lane

**Tensor Description**:
The mathematical shape, component structure, and index-space tags of a tensor Site Value, independent of its native storage or access representation. A Field's tensor description is unchanged when execution placement or access granularity changes.
_Avoid_: Standalone tensor storage, Field Site Proxy, backend value representation

**Field Handle**:
A reference to shared Field storage and its immutable Lattice association. Copying a handle shares the same Field; Whole-Field Assignment writes values into the destination Field's existing storage.
_Avoid_: Implicit deep copy, independent Field allocation

**Field Domain**:
The Domain of the Lattice on which a Field is constructed, fixed for the Field's lifetime. It determines valid Site Indices and the coverage of Whole-Field Assignment.
_Avoid_: Iteration filter, mutable checkerboard flag

**Field Expression**:
A deferred pointwise computation over Fields on conformable Lattices, with numeric scalars broadcast across that Domain. It retains shared Field handles and captured scalar values; Field values are read when the computation is evaluated.
_Avoid_: Temporary Field allocation, Field View, snapshot of Field values

**Field Arithmetic**:
Pointwise application of site-value arithmetic to Fields and Field Expressions. Operand order and grouping are preserved, and the result's site-value type follows the corresponding site operation and Numeric Promotion rules.
_Avoid_: Implicit reduction, stencil, concrete-type closure

**Pointwise Tensor Contraction**:
A tensor operation applied independently at every site, with a full trace, determinant, or norm producing a Numeric-valued Field on the operand's conformable Lattice. It contracts tensor components without combining lattice sites.
_Avoid_: Lattice Reduction, implicit global sum

**Lattice Reduction**:
An explicitly requested combination of values across a Lattice's selected sites, executed within an Execution Context. Tensor contraction within a site and combination across lattice sites are distinct operations.
_Avoid_: Pointwise Field Arithmetic, backend-selected placement

**Whole-Field Assignment**:
An assignment that writes a value to every site in a Field's Domain. Its enclosing Execution Context determines where it executes.
_Avoid_: Field View assignment, Site assignment, backend-selected placement

**Field View**:
A scoped, access-qualified handle to a Field that preserves its Lattice provenance, Domain, and site-value semantics. Its access lifetime ends when its owning scope exits, at the latest when its enclosing Execution Context exits; copied handles and Site Proxies do not extend that lifetime.
_Avoid_: Field copy, independent Field

**Field Site Proxy**:
Access to a Field's Site Value or a packed group of Site Values, exposing the numeric, vector, or tensor algebra of its site type as permitted by the Field View's access mode. Component access preserves those permissions, scope, and site provenance while exposing the algebra of the selected component.
_Avoid_: Site Index, independent Site Value, mandatory arithmetic-result type

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
A typed reference yielded by a Lattice's iteration space and valid only for Fields associated with a conformable Lattice. Its kind determines what kind of site value that access produces.
_Avoid_: Raw integer index, universal site number

**Scalar Site**:
A Site Index for one logical site in the current rank's portion of a Domain. Indexing a Field with a Scalar Site accesses one Site Value, whether numeric or tensor-valued.
_Avoid_: Local Site, scalar site number

**Packed Site**:
A Site Index for one group of Scalar Sites in a Domain's resolved site organization, with the Full Domain using the Lattice's Packed Geometry. Indexing a Field with a Packed Site produces the group's packed site value, independent of Execution Context.
_Avoid_: SIMD Site, packed site number

**Site Granularity**:
An explicit choice of Scalar or Packed that selects which Site Index kind a Domain's iteration space yields, with direct Lattice iteration using the Full Domain.
_Avoid_: Packing hint, backend vector width

**Execution Context**:
A required lexical scope selecting where its Whole-Field Assignments, Field Views, Parallel Site Loops, and Lattice Reductions execute. Quark defines Host and Accelerator Execution Contexts; the selected backend supplies their concrete execution and access constructs.
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
