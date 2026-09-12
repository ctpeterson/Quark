# Spin representation in Grid and QEX

Research date: 2026-09-12

Status: the user accepted `Spin[...]` as a mathematical index-space tag around a vector or matrix on 2026-09-12. Tensor parameter ordering, supported dimensions, and spin-specific operations remain recommendations for discussion; a complete tensor interface has not been accepted. Milestone 1 concerns portable contracts and adapter conformance; this report does not require backend storage or execution integration. See [ROADMAP.md](../../ROADMAP.md#milestone-1--portable-interface-and-backend-seam).

## Sources and limits

The detailed evidence comes from locally inspected primary source at QEX commit [`cb3dc8b`](https://github.com/jcosborn/qex/tree/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14) in `/home/curtyp/Software/scratch/qex`, and Grid-HISQ commit [`2b28342`](https://github.com/ctpeterson/Grid-HISQ/tree/2b2834244c867f6bbc7a048ca0983f2b8f971e40) in `/home/curtyp/Software/05-19-2026-Grid-HISQ`. Both working trees contain unrelated changes; the cited files are unmodified relative to these commits. Grid evidence is therefore about this Grid fork snapshot, not a claim that the latest upstream revision was inspected.

The online [official Grid tensor documentation][grid-doc] independently confirms recursive tensor nesting and positional Lorentz/Spin/Colour index semantics. Its documentation site labels the API documentation as work in progress dating from 2017. Online attempts to read the exact GitHub source pages failed with cache misses, so their pinned links identify locally inspected code, not successfully fetched web pages. [Grid documentation status](https://paboyle.github.io/Grid/docs/)

## Evidence: Spin identifies a tensor index space

QEX's public `spin.nim` exports `spinOld.nim`; the alternative `spinTensor` import is commented out. The active implementation creates a generic `Spin` wrapper, forwards vector/matrix shape queries, and implements arithmetic by operating on the wrapped objects and wrapping the result. `Spin2` and `Spin3` are aliases used in overloads, not two- and three-component spin types. [Public module][q-spin-entry], [wrapper, queries, and arithmetic][q-spin]

QEX's standard full fermion is a spin vector of colour vectors, with four spin components; its half fermion has two. The spin and colour sizes are independent. Its scalar and SIMD variants preserve the nesting and replace numeric leaf representations. [QEX QCD types][q-types]

```text
Spin[VectorArray[4, Color[VectorArray[nc, ComplexType[float64]]]]]
Spin[VectorArray[2, Color[VectorArray[nc, ComplexType[float64]]]]]
```

Grid represents the corresponding structure using nested `iScalar`, `iVector`, and `iMatrix` templates. Its QCD aliases reserve Lorentz, Spin, then Colour levels; scalar wrappers occupy inactive levels. `Ns` is four and `Nhs` is two. The aliases below retain a free numeric leaf type `L`. [Grid constants and QCD aliases][g-types]

| Meaning | Grid QCD representation |
| --- | --- |
| Spin vector | `iScalar<iVector<iScalar<L>, Ns>>` |
| Spin matrix | `iScalar<iMatrix<iScalar<L>, Ns>>` |
| Spin-colour vector | `iScalar<iVector<iVector<L, Nc>, Ns>>` |
| Half spin-colour vector | `iScalar<iVector<iVector<L, Nc>, Nhs>>` |
| Spin-colour matrix | `iScalar<iMatrix<iMatrix<L, Nc>, Ns>>` |
| Colour matrix, scalar in spin | `iScalar<iScalar<iMatrix<L, Nc>>>` |

Grid's spin-specific dispatch tests tensor depth, not merely whether a vector has length four. The scalar padding consequently participates in operator dispatch. Gamma operations recurse through other tensor levels until the spin level. [Spinor index predicate][g-types], [tensor depth traits][g-traits], [Gamma dispatch][g-dirac]

**Design inference:** `Spin` should carry the meaning of a tensor level, while `Vector` or `Matrix` supplies its shape and general algebra. A four-component untagged vector should not automatically acquire Dirac-spin semantics. The portable tag can map to a QEX wrapper or Grid's positional structure without exposing either implementation.

## Evidence: algebra and components remain recursive

QEX's spin multiplication delegates to the wrapped multiplication. Its matrix-vector and matrix-matrix routines contract matching dimensions using multiplication and accumulation on the component types. Thus a spin matrix is not merely a bag of independent numeric operations. Its components can themselves have colour algebra. QEX also defines colour-times-spin by applying the colour operand through the wrapped spin object and preserving the spin wrapper. [Spin arithmetic][q-spin], [matrix multiplication][q-mul], [colour-times-spin][q-colour-spin]

For component access, QEX removes the spin wrapper when indexing that spin level. An index carrying another wrapper traverses into the underlying structure and rewraps the result as Spin. The Colour wrapper has the analogous behavior. Grid exposes named `peekSpin`/`peekColour` operations selecting the corresponding tensor level. [Spin indexing][q-spin], [Colour indexing][q-colour], [Grid component operations][g-components]

**Design inference:** component conformance must be recursive, rather than requiring every component selection to be numeric. Selecting one spin component of a spin-colour vector yields a colour vector; selecting its colour component reaches the numeric leaf. Selecting colour first must retain the spin structure. For Field access, each step must also preserve access permissions, provenance, scope, and Scalar/Packed granularity, as required by Quark's [Field Site Proxy contract](../../CONTEXT.md).

**Design inference:** shape alone is insufficient to select a contraction. A spin matrix and colour matrix must act on their respective levels. Generic vector/matrix concepts should express shape, component type, and valid algebra; the Spin/Colour tags retain which mathematical space those operations concern. `FieldSiteProxy` should check that structure's capabilities, without enumerating every tagged nesting in a growing conditional.

## Evidence: spin size does not define all spin operations

QEX's active implementation constructs explicit 4×4 gamma matrices and rectangular 2×4 projection / 4×2 reconstruction matrices. Grid's basic `iMatrix<T,N>` is square; its half-spin projection and reconstruction facilities use operations converting between four- and two-component vectors. Both therefore express half-spin operations, but not with identical matrix representations. [QEX gamma and projection matrices][q-gamma], [Grid tensor class declarations][g-traits], [Grid half-spin operations][g-half]

Direct comparison of QEX's gamma constants with Grid's generated actions gives the correspondence `gamma1/2/3/4` to `GammaX/Y/Z/T`, with matching component signs in these snapshots. Both gamma-five actions have diagonal `(+1,+1,-1,-1)`. QEX's `gamma0` is identity, so blindly translating a gamma numeric suffix would be wrong. This is source-level comparison, not a compiled interoperability test. [QEX constants][q-gamma], [Grid gamma-five][g-gamma5], [Grid gamma-T][g-gammat], [Grid gamma-X][g-gammax], [Grid gamma-Y][g-gammay], [Grid gamma-Z][g-gammaz]

Grid additionally distinguishes directional projection normalization from chiral projection normalization in its half-spin code. A future common operation must specify its direction, sign, normalization, and full/half-spin domain, rather than inherit them from a backend spelling. [Grid half-spin normalization and operations][g-half]

## Agreed representation and proposed refinements

The agreed representation is a mathematical index-space tag around a vector or matrix: `Spin[Vector[...]]` and `Spin[Matrix[...]]`. The examples below propose explicit dimensions and recursively typed components; their detailed parameter syntax is not an implemented API:

```nim
type
  ColourVector = Color[Vector[3, Complex[D]]]
  Fermion = Spin[Vector[4, ColourVector]]
  HalfFermion = Spin[Vector[2, ColourVector]]
  SpinMatrix = Spin[Matrix[4, 4, Complex[D]]]
  Propagator = Spin[Matrix[4, 4, Color[Matrix[3, 3, Complex[D]]]]]
```

This recommendation follows the common spin-outside-colour structure in the [QEX][q-types] and [Grid][g-types] aliases. `Color` versus `Colour` spelling and generic parameter order remain choices for the proposed tensor oracle.

- Let tagged vector/matrix types satisfy their appropriate structural capability contracts. Readable site proxies expose that algebra; WriteDiscard access must not require reading operators merely to qualify as a proxy.
- Keep mathematical leaf kind and precision separate from execution-dependent representation. Tensor component selection changes mathematical structure; it does not select a packing lane. Both backends already provide scalar/SIMD leaf variants without changing the spin-colour structure. [QEX variants][q-types], [Grid leaf type mappings][g-traits]
- Treat ordinary spin scalars as having no active spin index initially. Do not require users to spell Grid's padding with a portable `Spin[Complex[D]]` wrapper. Add a spin-scalar marker later only if a portable operation needs that distinction.
- Start the shared spin contract with full-spin size four and half-spin size two where relevant. A generic Spin tag need not universally ban other dimensions, but it must not grant four-component gamma algebra to them. Unsupported combinations should reject explicitly.
- Do not make arbitrary rectangular spin matrices a prerequisite. QEX's rectangular projectors and Grid's specialized projection operations suggest a separate future projection/reconstruction contract when an oracle needs it.
- For a proposed Oracle C, start with a spin-colour vector and a colour or spin matrix: exercise whole-value algebra, nested component access down to numeric leaves, shape preservation, and access-mode rejection. Specify gamma conventions only if gamma operations enter that oracle.

The Spin tag is agreed; the additional contract recommendations above remain for discussion. This decision does not schedule implementation of new tensor machinery, freeze Oracle C, or change the boundary between Milestone 1 conformance and later adapter integration.

[grid-doc]: https://paboyle.github.io/Grid/docs/API/tensor_classes.html
[q-spin-entry]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/spin.nim#L1-L5
[q-spin]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/spinOld.nim#L1-L197
[q-types]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/qcdTypes.nim#L34-L102
[q-colour-spin]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/qcdTypes.nim#L142-L144
[q-colour]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/colorOld.nim#L1-L58
[q-mul]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/maths/matrixOps.nim#L490-L544
[q-gamma]: https://github.com/jcosborn/qex/blob/cb3dc8bd32bbcbb931618ddfc3db7d27b01e9d14/src/physics/spinOld.nim#L236-L319
[g-types]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/QCD.h#L51-L114
[g-traits]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/tensors/Tensor_traits.h#L31-L368
[g-dirac]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/spin/Dirac.h#L49-L115
[g-components]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/QCD.h#L412-L443
[g-half]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/spin/TwoSpinor.h#L35-L204
[g-gamma5]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/spin/Gamma.h#L90-L97
[g-gammat]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/spin/Gamma.h#L156-L163
[g-gammax]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/spin/Gamma.h#L288-L295
[g-gammay]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/spin/Gamma.h#L420-L427
[g-gammaz]: https://github.com/ctpeterson/Grid-HISQ/blob/2b2834244c867f6bbc7a048ca0983f2b8f971e40/Grid/qcd/spin/Gamma.h#L552-L559
