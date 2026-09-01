# Quark

The domain language for Quark, an experimental programming language for lattice field theory.

## Language

**Lattice**:
The geometry and layout of a finite site space, including how that space is decomposed for execution. A Lattice does not own the fields defined over it.
_Avoid_: Field container, lattice field

**Field**:
A lattice-associated collection with one value of a specified site type at each site. A Field is distinct from and not owned by its Lattice.
_Avoid_: Lattice, lattice object

**Whole-Field Assignment**:
An assignment that writes a value to every site of a Field. Its enclosing Execution Context determines where it executes.
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
A typed reference yielded by one Lattice's iteration space and valid only for Fields associated with that Lattice. Its kind determines what kind of site value that access produces.
_Avoid_: Raw integer index, universal site number

**Scalar Site**:
A Site Index for one scalar site assigned to the current rank by a Lattice layout. Indexing a Field with a Scalar Site produces one scalar site value.
_Avoid_: Local Site, scalar site number

**Packed Site**:
A Site Index for one layout-defined packed group of Scalar Sites. Indexing a Field with a Packed Site produces the group's packed site value, independent of Execution Context.
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
