# Tensor interface and backend compatibility

Date: 2026-09-12

Status: records source findings, implemented conformance, and the accepted architecture in [ADR 0008](../adr/0008-separate-tensor-algebra-from-lattice-reductions.md), [ADR 0009](../adr/0009-separate-tensor-descriptions-from-native-values.md), [ADR 0010](../adr/0010-parameterize-site-kind-statically.md), and [ADR 0011](../adr/0011-require-zero-abstraction-overhead.md). Tensor descriptions, unified Site declarations, and additional operation conformance still require implementation; the ADRs supersede the earlier expectation that public tensor names prescribe adapter-owned value storage.

This advances the interface design for [Milestone 1](../../ROADMAP.md#milestone-1--portable-interface-and-backend-seam). The [September 9 checkpoint](checkpoint-2026-09-09-field-design.md#field-decisions-and-user-priorities) already records the requirement that tensor representations preserve compatibility with backend physics operators without hidden representation conversions. The [Spin report](../research/grid-qex-spin-representation.md) records the accepted meaning of `Spin[...]` and the source evidence behind it.

## Source findings

Both backends provide generic vector and matrix families with compile-time dimensions:

| Backend | Vector | Matrix |
| --- | --- | --- |
| QEX | `VectorArray[N, T]`, static `N` | `MatrixArray[R, C, T]`, static `R` and `C` |
| Grid | `iVector<T, N>`, template parameter `N` | `iMatrix<T, N>`, square `N × N` |

QEX stores fixed-size Nim arrays and wraps them with `AsVector`/`AsMatrix`. Grid stores fixed-size C++ arrays. QEX's separate row and column dimensions are a capability difference from Grid's basic square matrix family. [QEX declarations][q-matrix], [Grid declarations][g-tensor]

Physics types retain additional structure. For a full spin-colour vector, with `Leaf` denoting the selected backend numeric representation:

```text
QEX:  Spin[VectorArray[4, Color[VectorArray[3, Leaf]]]]
Grid: iScalar<iVector<iVector<Leaf, 3>, 4>>
```

QEX uses actual Spin and Color wrappers. Grid's physics names alias particular nested tensor types, with scalar levels occupying inactive index spaces. A flat vector of twelve numbers does not preserve those structures. [QEX QCD types][q-types], [Grid Wilson types][g-wilson]

Grid's `FermionOperator<Impl>` accepts `Impl::FermionField`; `WilsonImpl` defines that as `Lattice<SiteSpinor>` with a specific nested site type. QEX's Wilson procedures accept generic Field families, but require the spin projection, reconstruction, and colour algebra used by their bodies. `newWilson(g, v)` derives its communicated type from `spproj1p(v[0])`. Structural conformance to Quark's vector operations alone does not establish either form of operator compatibility. [Grid operator interface][g-operator], [QEX Wilson construction][q-wilson]

These findings use the local QEX `cb3dc8b` and Grid-HISQ `2b28342` snapshots identified in the Spin report. The cited files were unmodified relative to those revisions when checked. They are source findings, not compiled interoperability results.

## Representation constraints

- Tensor dimensions and component structure remain available at compile time. Components can themselves be tagged vectors or matrices.
- `Spin[...]` identifies a vector or matrix's mathematical index space and retains its shape and component structure.
- Adapters select concrete types from the complete tagged structure, including the required numeric leaves. A portable tag need not introduce another runtime wrapper; Grid's required scalar padding belongs to its adapter.
- Supported physics types must retain compatibility with canonical backend Field and operator types. Passing a Field to an adapted operator must not require elementwise repacking merely to cross the interface.
- Generic tensor conformance and compatibility with a particular physics operator are distinct checks. Shape alone does not establish spin meaning, supported precision, or the operator's required Lattice association.

## Responsibilities of `base/tensor.nim`

The initial implementation follows the numeric interface pattern: `VectorObject[T, N]` and `MatrixObject[T, N]` classify structure; `VectorArithmetic[T, N]` and `MatrixArithmetic[T, N]` check readable algebra. `T` is the immediate mathematical component type and `N` is a positive static dimension. The matrix contract is square, following the original sketch. Native value families remain adapter-owned; public mathematical descriptions follow ADR 0009.

Classification should expose only the facts needed to describe and check the mathematical value:

- vector length, or matrix row and column counts, as compile-time values;
- the mathematical component type, which can recursively be numeric or tensor-valued;
- spin identity where the type represents the agreed Spin meaning.

Ordinary vectors and matrices require no index-space metadata. `SpinObject[T]` distinguishes spin tensors from ordinary tensors of the same shape through a compile-time boolean `isSpin = true`. Only spin types need to provide that query. A colour tag remains a proposal; these contracts do not introduce a general tagging system.

Readable arithmetic capabilities should check component access and the selected operations' result structure. Component access need not return the exact concrete type named by the mathematical component declaration. A Field component proxy can provide the corresponding algebra while retaining access mode, scope, provenance, and Scalar/Packed granularity. Selecting a spin component can return a colour vector; numeric algebra applies when selection reaches a numeric leaf.

Tensor arithmetic needs shape-aware result rules. Addition of compatible vectors preserves vector structure. Matrix–vector multiplication returns a vector; matrix–matrix multiplication contracts compatible dimensions. Tagged operands act on their corresponding index spaces. These relationships also depend on component algebra, including operand order for matrix-valued components. Do not copy the numeric closed-operation list or require every multiplication to return the operand's shape. Validate cross-type operations through focused operand-pair conformance checks as their syntax is agreed.

`FieldSiteProxy` selects vector or matrix arithmetic from its mathematical site type, as it selects numeric arithmetic. These branches precede the numeric `T.precision` gate: tensor classification describes shape and components, with numeric kind and precision checked at the leaves. Tagged tensor types participate through those same capabilities. WriteDiscard access must retain structural metadata and writable component access without requiring readable arithmetic. Field-specific permissions and provenance remain the responsibility of the Field interface.

Public `Vector[...]`, `Matrix[...]`, and tagged descriptions follow ADR 0009; their concrete native value representations belong to adapters. `base/tensor.nim` should not prescribe their member arrays, backend type names, Field storage, or an expression representation. Backend mapping may inspect the complete mathematical site type rather than mechanically translate each wrapper in isolation.

## Implemented queries and conformance

- `componentType` names the immediate mathematical component type.
- `tensorKind` is the static `tkVector` or `tkMatrix` value of `TensorKind`. A matrix can also expose `len` without being classified as a vector.
- `len` gives a vector's static dimension. A square matrix's static `nrows` and `ncols` must both equal `N`.
- `isSpin` is a compile-time boolean required to be true by `SpinObject[T]`. Ordinary vector and matrix types need not expose it; no marker objects are required.
- `SpinObject[T]` matches a Spin-tagged vector or matrix with the wrapped mathematical tensor T's shape and component structure. It requires metadata, without a `wrappedType` member or readable operations.

Structure classification recursively checks supported numeric/vector/matrix components without requiring reads. Arithmetic checks indexed component algebra, unary plus/minus, addition/subtraction, and multiplication on either side by the numeric leaf type at its declared precision. Square-matrix arithmetic also checks same-type matrix multiplication. Results preserve mathematical component types and shape; when the source satisfies `SpinObject`, results must retain that spin identity. Concrete result types may differ.

The recursive structural and arithmetic checks use private compile-time generic helpers. Directly nesting all of these concept matches reaches Nim 2.2.8's concept-matching depth limit even for spin-colour tensors. These helpers participate only in conformance and do not implement tensor operations or an expression representation.

`tests/tensorConcept.nim` uses independent structural witnesses with both adapters' numeric families. It checks static dimensions, square shape, nested spin/colour structure, numeric component proxies, metadata-only access, distinct and chainable arithmetic-result types, and rejection of missing operations or lost spin identity. These are interface checks, not numerical tensor execution or native operator acceptance.

Field Site Proxy conformance recursively checks component mathematical types, access modes, and Scalar/Packed index types, retaining tensor shape and spin identity at each level. WriteDiscard checks component handles without requiring readable arithmetic. `tests/fieldTensorConcept.nim` exercises these contracts through independent proxies and complete Field/View witnesses; its tensor signatures share `tests/support/tensorFixtures.nim` with the tensor tests.

## Next decisions

### Site descriptions and concrete access types — September 12 follow-up

The user questioned whether `Vector[T, N]` and `Matrix[T, N]` should prescribe concrete tensor values at all. The direction accepted in ADR 0009 is to use these names as mathematical site-type descriptions in `Field[...]`, retaining the existing shape/component concepts. A description still needs to be a proper Nim type for the nested generic argument, but it need not contain an array, have runtime instances, or provide value arithmetic. ADR 0009 supersedes the earlier expectation of public adapter-owned tensor value families; Oracle C's spelling does not require standalone storage.

Oracle C currently uses these names in Field construction, nested aliases, and structural assertions. It performs arithmetic through indexed views. A disposable Nim 2.2.8 fixture verified that metadata-only vector/matrix descriptions satisfy the existing structural concepts, including nested vectors, while lacking `VectorArithmetic`; a Field handle parameterized by such a description need not store a description instance. This establishes type-level feasibility, not native storage or operator compatibility.

Keep three responsibilities distinct:

- The mathematical description states shape, numeric leaves, and Spin identity, independently of execution placement.
- The adapter resolves Field storage from that description and the Lattice's resolved Layout. Storage must already have a concrete native representation when the Field is allocated.
- Access through a View resolves a concrete Field Site Proxy using the description, Scalar/Packed Site kind, Host/Accelerator Execution Context, and access mode. Arithmetic results and tensor-valued reduction results can be native values or expressions without retaining assignable Field access.

Thus a Field Site Proxy is not the only concrete type needed internally. An expression such as `a[n] + b[n]` and a tensor-valued global sum still have concrete result types, which callers can infer without a portable standalone tensor-storage API. The tensor concepts constrain those results as appropriate. Selecting a tensor component must continue to expose its mathematical component description while preserving the relevant access capabilities.

The existing common scaffold derives arithmetic from operations on `default(siteType)`. That shortcut assumes the description itself supports value arithmetic and must be revisited if descriptions are separated from native values. Do not add dummy arithmetic to descriptions merely to preserve this scaffold. This remains interface work in Milestone 1; source types have not been migrated by this note.

Vector Hermitian inner products are now a required Milestone 1 capability, alongside outer products. `inner(v, w) = sum_i conj(v_i) * w_i`, with recursive contraction for supported nested vector shapes, must produce the promoted Numeric result. Pointwise Field application preserves the Lattice; a global inner product requests a separate lattice reduction. Tests must distinguish conjugating the first operand from conjugating the second and cover mixed precision/kind, shape, tags, and view permissions. The public spelling remains to be settled with the other operators.

### One parameterized Site type

The representation accepted in ADR 0010 is a single family `Site[L; K: static IterationSpace]`. `lattice.sites(Scalar)` yields `Site[L, Scalar]`; `lattice.sites(Packed)` yields `Site[L, Packed]`. `K` remains a compile-time parameter, so the two instantiations are distinct types without requiring a runtime kind discriminator. Existing `ScalarSite[L]` and `PackedSite[L]` names can remain aliases to preserve frozen oracle assertions while removing the duplicated object declarations.

The Site Index continues to retain Lattice provenance. Host/Accelerator belongs to the enclosing Execution Context and view access, independently of Scalar/Packed. Unifying the declaration must not make a single runtime-tagged index accepted wherever either access kind is expected. A disposable Nim 2.2.8 fixture confirmed generic acceptance of either instantiation and compile-time rejection of Packed where Scalar is required. It did not migrate the existing iterators, Field concepts, adapters, or fixtures.

### Zero abstraction overhead — accepted constraint

[ADR 0011](../adr/0011-require-zero-abstraction-overhead.md) is authoritative: Quark adds no runtime work or storage compared with an equivalent direct-backend program preserving the same semantics. It specifies optimized-code and native-reference evidence, covers work outside kernels as well as inside them, and preserves lifetime and provenance guarantees. The current leases and access checks remain scaffold limitations to resolve before claiming native compliance.

The description split, unified Site family, and zero-overhead constraint are accepted architectural decisions. Implementation and native performance evidence remain outstanding; reduction syntax and the unresolved algebra definitions remain open as recorded in ADRs 0007 and 0008.

Milestone 1 has been reopened for linear-algebra conformance: trace, determinant, squared norms, infinity norms, and Hermitian outer products (`v * w†`), together with separately scoped lattice reductions. Full tensor contractions on Fields must produce Numeric-valued Fields on conformable Lattices. Native backend definitions guide the norm contracts; partial traces and determinants of nested matrix structures need explicit meaning before conformance is added. Vector Hermitian inner products are required in this slice; adjoint and conjugation remain candidates. See the [backend research](../research/grid-qex-reductions.md) and [interface proposals](reduction-interface.md). These requirements are pending work, not capabilities already proved by the existing arithmetic concepts.

The user's expanded Oracle C now fixes `Vector[T, N]`, square `Matrix[T, N]`, and `Spin[T]`, with chained component selection for nested tensors and matrix-vector products preserving the corresponding shape and Spin identity. These are frozen acceptance requirements; resolving their type arguments and implementing the additional operand-pair conformance checks remain pending. As discussed above, those type arguments need not prescribe standalone tensor value storage. Rectangular matrices need a separate interface extension; the square contract rejects them.

Concrete adapter scope and indexing checks now enforce lifetime and Lattice instance provenance beyond structural matching; see the [Milestone 1 closeout](milestone-1-closeout.md). Native operator compatibility remains an adapter requirement, with integration at its scheduled milestone. Oracle C is now frozen as the tensor Field acceptance target. See the [oracle matrix](../../oracle/README.md) for its milestone assignment and current limits.

[q-matrix]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/maths/matrixConcept.nim#L115-L123
[q-types]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/qcdTypes.nim#L48-L102
[q-wilson]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/wilsonD.nim#L288-L325
[g-tensor]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/tensors/Tensor_class.h#L188-L303
[g-wilson]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/action/fermion/WilsonImpl.h#L56-L74
[g-operator]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/action/fermion/FermionOperator.h#L40-L77
