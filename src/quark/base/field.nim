#[
Field conformance

src: quark/base/field.nim
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

MIT License

Copyright (c) 2026 Curtis Taylor Peterson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]#

## Fields, access-qualified Views, and recursive Site Proxies
## ==========================================================
##
## A Field is storage associated with an immutable Lattice and a mathematical
## site-value type. Fields are separate from Lattices. Copies of a Field handle
## share that Field, whereas Whole-Field Assignment writes values into existing
## destination storage. Associated Lattices must be conformable whenever an
## operation combines Field values or uses a Site Index for access.
##
## ``FieldObject[T]`` classifies the site type, Lattice association, and the
## availability of Views for all three access modes. ``FieldViewObject[T]``
## classifies a View's site type, Lattice, static mode, and access through both
## Scalar and Packed Site Indices. Construction and assignment compatibility
## are separate conformance requirements, not consequences of matching either
## concept.
##
## The modes have distinct permission and data-preservation rules:
##
## * ``Read`` makes existing values available and forbids modification.
## * ``ReadWrite`` preserves existing values and permits partial or complete
##   updates; untouched components and sites retain their values.
## * ``WriteDiscard`` makes existing values unavailable and requires assignment
##   of every element of the viewed region before closure. Reading through it,
##   including an update that consumes an old value, is not permitted.
##
## ``FieldSiteProxy[T, S]`` exposes the algebra of mathematical site type ``T``
## through Site Index kind ``S``. Readable numeric sites provide the corresponding
## Integer, Real, or Complex arithmetic. Tensor sites provide vector or
## square-matrix structure and the permitted algebra. Selecting a component
## recursively retains mode and index type, and preserves Spin identity where
## present. A write-only tensor still exposes component handles so every numeric
## leaf can be assigned without reading an old value.
##
## Views and indexed access require an explicit Execution Context. A View closes
## when its owning scope ends, no later than the enclosing ``within`` block.
## Copies and component proxies cannot extend access lifetime. Reopening a View
## makes the required values available in its requested context according to its
## mode. These rules describe observable behavior; native storage, access,
## synchronization, validation, and release use backend facilities wherever they
## provide the required semantics.
##
## A concept verifies static capability and metadata, not instance provenance,
## actual cleanup, WriteDiscard coverage, or numerical correctness. Focused
## operation-pair checks and runtime acceptance complement classification.
## Arithmetic results may be independent expression values; they need not remain
## assignable Field Site Proxies or introduce a particular expression framework.


import lattice
import iteration
import numeric
import tensor
import execution

type ViewMode* = enum
  ## The mode in which a Field is accessed through FieldView
  Read =         0 ## Read-only access
  WriteDiscard = 1 ## Write access that discards previous content
  ReadWrite =    2 ## Read and write access

func siteComponent[C,T,S](
  value: typedesc[C];
  expected: typedesc[T];
  index: typedesc[S];
  access: static ViewMode
): bool {.compileTime.}

type
  FieldSiteProxy*[T,S] = concept site, type P
    ## Access to Field sites with the algebra of T, qualified by the view mode.
    ## S identifies one site or a packed group independently of tensor shape.
    ## Tensor components retain the mode and S recursively, with numeric algebra
    ## at the leaves. WriteDiscard requires component handles without reads.
    P.siteType is T
    P.indexType is S
    S is Site

    const access = site.mode
    access is ViewMode

    when compiles(T.tensorKind):
      mixin `[]`

      type Element = T.componentType

      const size = T.len
      const kind = T.tensorKind
      kind is TensorKind

      when T is SpinObject[T]: P is SpinObject[T]

      when kind == tkVector:
        T is VectorObject[Element, size]
        when access == WriteDiscard: site is VectorObject[Element, size]
        else: site is VectorArithmetic[Element, size]
        siteComponent(typeof(site[0]), Element, S, access)
      elif kind == tkMatrix:
        T is MatrixObject[Element, size]
        when access == WriteDiscard: site is MatrixObject[Element, size]
        else: site is MatrixArithmetic[Element, size]
        siteComponent(typeof(site[0, 0]), Element, S, access)
      else: false
    elif compiles(T.precision):
      const prec = T.precision
      prec is Precision
      when T is IntegerNumber[prec]:
        when access != WriteDiscard: site is IntegerArithmetic[prec]
      elif T is RealNumber[prec]:
        when access != WriteDiscard: site is RealArithmetic[prec]
      elif T is ComplexNumber[prec]:
        when access != WriteDiscard: site is ComplexArithmetic[prec]
      else: false # Unsupported site algebra rejects concept matching.
    else: false # Unsupported site types reject concept matching.

  FieldViewObject*[T] = concept view, type V
    ## FieldView with site-value type T and immutable Lattice association. Provides
    ## scalar or packed site access to underlying field data, represented at the
    ## source level as a FieldSiteProxy.
    ##
    ## Upon opening view, checks of data synchronization between host and
    ## accelerator memory are performed based on state of field when a view of
    ## the field was last closed (by going out of scope).
    V.siteType is T

    view.lattice is Lattice

    const mode = view.mode # view mode is static
    mode is ViewMode

    type ScalarIndex = ScalarSite[typeof(view.lattice)]
    type PackedIndex = PackedSite[typeof(view.lattice)]
    type ScalarAccess = typeof(block:
      within Host: view[default(ScalarIndex)])
    type PackedAccess = typeof(block:
      within Host: view[default(PackedIndex)])
    ScalarAccess is FieldSiteProxy[T, ScalarIndex]
    PackedAccess is FieldSiteProxy[T, PackedIndex]
    default(ScalarAccess).mode == view.mode
    default(PackedAccess).mode == view.mode

  FieldObject*[T] = concept field, type FieldType
    ## A Field with site-value type T and an immutable Lattice association.
    ## Copies share the same Field. Construction is checked separately;
    ## structural matching alone cannot establish ownership or provenance.
    FieldType.siteType is T
    field.lattice is Lattice

    type ReadView = typeof(block:
      within Host: field.view(ViewMode.Read))
    type DiscardView = typeof(block:
      within Host: field.view(ViewMode.WriteDiscard))
    type UpdateView = typeof(block:
      within Host: field.view(ViewMode.ReadWrite))
    ReadView is FieldViewObject[T]
    DiscardView is FieldViewObject[T]
    UpdateView is FieldViewObject[T]
    default(ReadView).mode == ViewMode.Read
    default(DiscardView).mode == ViewMode.WriteDiscard
    default(UpdateView).mode == ViewMode.ReadWrite

# keep recursive component matching within Nim's concept-matching depth limit
func siteComponent[C,T,S](
  value: typedesc[C];
  expected: typedesc[T];
  index: typedesc[S];
  access: static ViewMode
): bool {.compileTime.} =
  return when C is FieldSiteProxy[T,S]: default(C).mode == access else: false

when isMainModule:
  import std/unittest

  # Signature witness for the portable contract; no native layout or storage.
  type
    TestGeometry = object
    TestPartition = object
    TestLattice[K: static Domain] = ref object
      identity: int
  func len(g: TestGeometry): int = 2
  func volume(g: TestGeometry): int = 24
  func `[]`(g: TestGeometry; i: int): int = [4, 6][i]
  func len(p: TestPartition): int = 2
  func partitions(p: TestPartition): int = 1
  func `[]`(p: TestPartition; i: int): int = 1
  template domain[K](l: TestLattice[K]): Domain = K
  func geometry[K](l: TestLattice[K]): TestGeometry = TestGeometry()
  func rankGeometry[K](l: TestLattice[K]): TestGeometry = TestGeometry()
  func packedGeometry[K](l: TestLattice[K]): TestGeometry = TestGeometry()
  func rankPartition[K](l: TestLattice[K]): TestPartition = TestPartition()
  func packedPartition[K](l: TestLattice[K]): TestPartition = TestPartition()
  func dimensions[K](l: TestLattice[K]): int = 2
  func conformable[A, B](a: TestLattice[A]; b: TestLattice[B]): bool =
    when A == B: a == b
    else: false

  # Independent structural fixtures have no newField constructor. Classification
  # must not demand construction, nor confuse concept parameters with the matched
  # concrete type. These are not ownership or native storage implementations.
  type
    Defect = enum
      valid, missingLattice, wrongSiteType, missingPackedAccess,
      wrongIndexType, wrongProxySiteType, wrongViewMode, wrongProxyMode,
      runtimeMode, missingBinaryArithmetic, wrongResultKind, wrongPrecision,
      missingScalarAccess, wrongViewSiteType, wrongViewLattice,
      wrongScalarMode, wrongPackedMode, missingReadView, missingDiscardView, missingUpdateView
    FixtureNumber[P: static Precision; K: static NumericKind] = object
    FixtureReal[P: static Precision] = FixtureNumber[P, nkReal]
    FixtureInteger[P: static Precision] = FixtureNumber[P, nkInteger]
    FixtureComplex[P: static Precision] = FixtureNumber[P, nkComplex]
    FixtureLattice = TestLattice[EvenParity]
    ScalarIndex = ScalarSite[FixtureLattice]
    PackedIndex = PackedSite[FixtureLattice]
    FixtureField[T; D: static Defect] = object
    FixtureView[T; D: static Defect; M: static ViewMode] = object
      runtimeAccess: ViewMode
    FixtureSite[T, S; D: static Defect; M: static ViewMode] = object

  template precision[P, K](T: typedesc[FixtureNumber[P, K]]): Precision = P
  template numericKind[P, K](T: typedesc[FixtureNumber[P, K]]): NumericKind = K
  template realType[P, K](T: typedesc[FixtureNumber[P, K]]): typedesc = FixtureReal[P]
  func re[P, K](v: FixtureNumber[P, K]): FixtureReal[P] = FixtureReal[P]()
  func im[P, K](v: FixtureNumber[P, K]): FixtureReal[P] = FixtureReal[P]()

  template precision[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): Precision =
    when D == wrongPrecision: H
    else: T.precision
  template numericKind[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): NumericKind = T.numericKind

  template defineArithmetic(symbol: untyped) =
    func symbol[ValueType, SiteType; DefectKind, Access](a: FixtureSite[ValueType, SiteType, DefectKind, Access]): ValueType =
      when Access == WriteDiscard:
        {.error: "write-only fixture".}
      ValueType()
    func symbol[ValueType, SiteType; DefectKind, Access](a, b: FixtureSite[ValueType, SiteType, DefectKind, Access]): auto =
      when Access == WriteDiscard or DefectKind == missingBinaryArithmetic:
        {.error: "fixture operation unavailable".}
      when DefectKind == wrongResultKind: 0
      else: ValueType()

  defineArithmetic(`+`)
  defineArithmetic(`-`)
  defineArithmetic(`*`)
  defineArithmetic(`/`)
  defineArithmetic(`div`)
  defineArithmetic(`mod`)

  template realType[T, S, D, M](V: typedesc[FixtureSite[T, S, D, M]]): typedesc = T.realType
  func re[T, S, D, M](v: FixtureSite[T, S, D, M]): auto =
    when M == WriteDiscard: {.error: "write-only real projection".}
    else: default(T.realType)
  func im[T, S, D, M](v: FixtureSite[T, S, D, M]): auto =
    when M == WriteDiscard: {.error: "write-only imaginary projection".}
    else: default(T.realType)

  template siteType[T; D](F: typedesc[FixtureField[T, D]]): typedesc =
    when D == wrongSiteType: int
    else: T

  template siteType[T; D, M](V: typedesc[FixtureView[T, D, M]]): typedesc =
    when D == wrongViewSiteType: int
    else: T

  template siteType[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): typedesc =
    when D == wrongProxySiteType: int
    else: T

  template indexType[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): typedesc =
    when D == wrongIndexType: int
    else: S

  func lattice[T; D](f: FixtureField[T, D]): auto =
    when D == missingLattice: 0
    else: FixtureLattice()

  func lattice[T; D, M](v: FixtureView[T, D, M]): auto =
    when D == wrongViewLattice: 0
    else: FixtureLattice()

  template mode[T; D, M](v: FixtureView[T, D, M]): ViewMode =
    when D == runtimeMode: v.runtimeAccess
    else: M

  template mode[T, S; D, M](p: FixtureSite[T, S, D, M]): ViewMode =
    when D == wrongProxyMode or (D == wrongScalarMode and S is ScalarIndex) or
         (D == wrongPackedMode and S is PackedIndex): Read
    else: M

  func view[T; D](f: FixtureField[T, D]; access: static ViewMode): auto =
    when (D == missingReadView and access == Read) or
         (D == missingDiscardView and access == WriteDiscard) or
         (D == missingUpdateView and access == ReadWrite):
      {.error: "view mode unavailable".}
    elif D == wrongViewMode: FixtureView[T, D, Read]()
    else: FixtureView[T, D, access]()

  func `[]`[T; D, M](v: FixtureView[T, D, M]; s: ScalarIndex): auto =
    when D == missingScalarAccess: 0
    else: FixtureSite[T, ScalarIndex, D, M]()

  func `[]`[T; D, M](v: FixtureView[T, D, M]; s: PackedIndex): auto =
    when D == missingPackedAccess: 0
    else: FixtureSite[T, PackedIndex, D, M]()


  suite "numeric Field classification":
    test "Integer Fields support H sites in all modes":
      type T = FixtureInteger[H]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Integer Fields support S sites in all modes":
      type T = FixtureInteger[S]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Integer Fields support D sites in all modes":
      type T = FixtureInteger[D]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Complex Fields support H sites in all modes":
      type T = FixtureComplex[H]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Complex Fields support S sites in all modes":
      type T = FixtureComplex[S]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Complex Fields support D sites in all modes":
      type T = FixtureComplex[D]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Field and all view modes accept H sites":
      type T = FixtureReal[H]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Field and all view modes accept S sites":
      type T = FixtureReal[S]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Field and all view modes accept D sites":
      type T = FixtureReal[D]
      check FixtureField[T, valid] is FieldObject[T]
      check FixtureView[T, valid, Read] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, Read] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, Read] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, ReadWrite] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, ReadWrite] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, ReadWrite] is FieldSiteProxy[T, PackedIndex]
      check FixtureView[T, valid, WriteDiscard] is FieldViewObject[T]
      check FixtureSite[T, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check FixtureSite[T, PackedIndex, valid, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    test "Field classification does not require a constructor":
      type F = FixtureField[FixtureReal[D], valid]
      check F is FieldObject[FixtureReal[D]]
      check not compiles(F.newField(FixtureLattice()))

    test "Field type parameters require the exact site type":
      check FixtureField[FixtureReal[S], valid] isnot FieldObject[FixtureReal[D]]
      check FixtureView[FixtureReal[S], valid, Read] isnot FieldViewObject[FixtureReal[D]]

    test "scalar and packed proxy types cannot substitute for one another":
      check FixtureSite[FixtureReal[D], ScalarIndex, valid, Read] isnot
        FieldSiteProxy[FixtureReal[D], PackedIndex]
      check FixtureSite[FixtureReal[D], PackedIndex, valid, Read] isnot
        FieldSiteProxy[FixtureReal[D], ScalarIndex]

    test "unrelated and unsupported values reject Field classification":
      check int isnot FieldObject[FixtureReal[D]]
      check FixtureField[string, valid] isnot FieldObject[string]
      check FixtureView[string, valid, WriteDiscard] isnot FieldViewObject[string]

  suite "Field and view capability rejection":
    test "Field classification rejects missingLattice":
      check FixtureField[FixtureReal[D], missingLattice] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongSiteType":
      check FixtureField[FixtureReal[D], wrongSiteType] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects missingPackedAccess":
      check FixtureField[FixtureReal[D], missingPackedAccess] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects missingScalarAccess":
      check FixtureField[FixtureReal[D], missingScalarAccess] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongIndexType":
      check FixtureField[FixtureReal[D], wrongIndexType] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongProxySiteType":
      check FixtureField[FixtureReal[D], wrongProxySiteType] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongViewMode":
      check FixtureField[FixtureReal[D], wrongViewMode] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongProxyMode":
      check FixtureField[FixtureReal[D], wrongProxyMode] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects runtimeMode":
      check FixtureField[FixtureReal[D], runtimeMode] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects missingBinaryArithmetic":
      check FixtureField[FixtureReal[D], missingBinaryArithmetic] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongResultKind":
      check FixtureField[FixtureReal[D], wrongResultKind] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongPrecision":
      check FixtureField[FixtureReal[D], wrongPrecision] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongViewSiteType":
      check FixtureField[FixtureReal[D], wrongViewSiteType] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongViewLattice":
      check FixtureField[FixtureReal[D], wrongViewLattice] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongScalarMode":
      check FixtureField[FixtureReal[D], wrongScalarMode] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects wrongPackedMode":
      check FixtureField[FixtureReal[D], wrongPackedMode] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects missingReadView":
      check FixtureField[FixtureReal[D], missingReadView] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects missingDiscardView":
      check FixtureField[FixtureReal[D], missingDiscardView] isnot FieldObject[FixtureReal[D]]
    test "Field classification rejects missingUpdateView":
      check FixtureField[FixtureReal[D], missingUpdateView] isnot FieldObject[FixtureReal[D]]
    test "view classification independently rejects missingScalarAccess":
      check FixtureView[FixtureReal[D], missingScalarAccess, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects missingPackedAccess":
      check FixtureView[FixtureReal[D], missingPackedAccess, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects wrongIndexType":
      check FixtureView[FixtureReal[D], wrongIndexType, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects wrongProxySiteType":
      check FixtureView[FixtureReal[D], wrongProxySiteType, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects wrongViewSiteType":
      check FixtureView[FixtureReal[D], wrongViewSiteType, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects wrongViewLattice":
      check FixtureView[FixtureReal[D], wrongViewLattice, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects wrongScalarMode":
      check FixtureView[FixtureReal[D], wrongScalarMode, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects wrongPackedMode":
      check FixtureView[FixtureReal[D], wrongPackedMode, ReadWrite] isnot FieldViewObject[FixtureReal[D]]
    test "view classification independently rejects runtimeMode":
      check FixtureView[FixtureReal[D], runtimeMode, ReadWrite] isnot FieldViewObject[FixtureReal[D]]

  suite "access-qualified numeric proxies":
    test "WriteDiscard does not require readable arithmetic":
      check FixtureSite[FixtureReal[D], ScalarIndex, missingBinaryArithmetic, WriteDiscard] is
        FieldSiteProxy[FixtureReal[D], ScalarIndex]
      check FixtureSite[FixtureReal[D], PackedIndex, missingBinaryArithmetic, WriteDiscard] is
        FieldSiteProxy[FixtureReal[D], PackedIndex]
      check not compiles(+default(FixtureSite[FixtureReal[D], ScalarIndex, valid, WriteDiscard]))

    test "both readable modes require numeric arithmetic":
      check FixtureSite[FixtureReal[D], ScalarIndex, missingBinaryArithmetic, Read] isnot
        FieldSiteProxy[FixtureReal[D], ScalarIndex]
      check FixtureSite[FixtureReal[D], ScalarIndex, missingBinaryArithmetic, ReadWrite] isnot
        FieldSiteProxy[FixtureReal[D], ScalarIndex]

    test "discard mode still requires supported site algebra":
      check FixtureSite[string, ScalarIndex, valid, WriteDiscard] isnot FieldSiteProxy[string, ScalarIndex]

    test "discard mode still requires site index provenance type":
      check FixtureSite[FixtureReal[D], int, valid, WriteDiscard] isnot FieldSiteProxy[FixtureReal[D], int]
      check FixtureSite[FixtureReal[D], ScalarIndex, wrongIndexType, WriteDiscard] isnot
        FieldSiteProxy[FixtureReal[D], ScalarIndex]

    test "a valid component must also have the requested mode":
      type T = FixtureReal[D]
      type C = FixtureSite[T, ScalarIndex, valid, Read]
      static:
        doAssert siteComponent(C, T, ScalarIndex, Read)
        doAssert not siteComponent(C, T, ScalarIndex, ReadWrite)
        doAssert not siteComponent(C, T, PackedIndex, Read)
        doAssert not siteComponent(C, FixtureReal[S], ScalarIndex, Read)

  # Minimal tensor signatures isolate recursive Field proxy requirements from
  # the tensor module's own arithmetic tests. These handles are write-only.
  type
    TensorDefect = enum
      tensorValid, wrongShape, lostMode, lostIndex, plainValue, noSelection, lostSpin
    TestTensor[T; N: static int; K: static TensorKind; Spin: static bool = false] = object
    TensorProxy[T, I; M: static ViewMode; F: static TensorDefect = tensorValid] = object
  template tensorKind[T, N, K, Spin](V: typedesc[TestTensor[T, N, K, Spin]]): TensorKind = K
  template componentType[T, N, K, Spin](V: typedesc[TestTensor[T, N, K, Spin]]): typedesc = T
  template len[T, N, K, Spin](V: typedesc[TestTensor[T, N, K, Spin]]): int = N
  template nrows[T, N, K, Spin](V: typedesc[TestTensor[T, N, K, Spin]]): int = N
  template ncols[T, N, K, Spin](V: typedesc[TestTensor[T, N, K, Spin]]): int = N
  template isSpin[T, N, K, Spin](V: typedesc[TestTensor[T, N, K, Spin]]): bool = Spin
  template siteType[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): typedesc = T
  template indexType[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): typedesc = I
  template mode[T, I, M, F](v: TensorProxy[T, I, M, F]): ViewMode = M
  template tensorKind[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): TensorKind = T.tensorKind
  template componentType[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): typedesc = T.componentType
  template len[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): int =
    when F == wrongShape: T.len + 1
    else: T.len
  template nrows[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): int = T.nrows
  template ncols[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): int =
    when F == wrongShape: T.ncols + 1
    else: T.ncols
  template isSpin[T, I, M, F](V: typedesc[TensorProxy[T, I, M, F]]): bool =
    when F == lostSpin: false
    else: T.isSpin
  template selected(T, I, M, F: untyped): untyped =
    when F == noSelection: {.error: "missing component access".}
    elif F == plainValue: default(T.componentType)
    elif F == lostMode: TensorProxy[T.componentType, I, Read]()
    elif F == lostIndex: TensorProxy[T.componentType, int, M]()
    else: TensorProxy[T.componentType, I, M]()
  func `[]`[T, I, M, F](v: TensorProxy[T, I, M, F]; i: int): auto = selected(T, I, M, F)
  func `[]`[T, I, M, F](v: TensorProxy[T, I, M, F]; i, j: int): auto = selected(T, I, M, F)

  suite "recursive write-only tensor proxies":
    template accepts(T: typedesc) =
      check TensorProxy[T, ScalarIndex, WriteDiscard] is FieldSiteProxy[T, ScalarIndex]
      check TensorProxy[T, PackedIndex, WriteDiscard] is FieldSiteProxy[T, PackedIndex]
    template rejects(T: typedesc; flaw: static TensorDefect) =
      check TensorProxy[T, ScalarIndex, WriteDiscard, flaw] isnot FieldSiteProxy[T, ScalarIndex]
      check TensorProxy[T, PackedIndex, WriteDiscard, flaw] isnot FieldSiteProxy[T, PackedIndex]

    test "vectors retain scalar and packed access":
      accepts(TestTensor[FixtureReal[D], 3, tkVector])

    test "matrices retain scalar and packed access":
      accepts(TestTensor[FixtureReal[D], 3, tkMatrix])

    test "nested spin tensors retain recursive handles":
      type Inner = TestTensor[FixtureReal[D], 3, tkVector]
      accepts(TestTensor[Inner, 4, tkVector, true])
      accepts(TestTensor[TestTensor[Inner, 4, tkMatrix, true], 2, tkVector])

    test "a write-only tensor does not satisfy readable proxy modes":
      type T = TestTensor[FixtureReal[D], 3, tkVector]
      check TensorProxy[T, ScalarIndex, Read] isnot FieldSiteProxy[T, ScalarIndex]
      check TensorProxy[T, PackedIndex, ReadWrite] isnot FieldSiteProxy[T, PackedIndex]
    test "vector and matrix proxies reject wrongShape":
      rejects(TestTensor[FixtureReal[D], 4, tkVector, true], wrongShape)
      rejects(TestTensor[FixtureReal[D], 4, tkMatrix, true], wrongShape)
    test "vector and matrix proxies reject lostMode":
      rejects(TestTensor[FixtureReal[D], 4, tkVector, true], lostMode)
      rejects(TestTensor[FixtureReal[D], 4, tkMatrix, true], lostMode)
    test "vector and matrix proxies reject lostIndex":
      rejects(TestTensor[FixtureReal[D], 4, tkVector, true], lostIndex)
      rejects(TestTensor[FixtureReal[D], 4, tkMatrix, true], lostIndex)
    test "vector and matrix proxies reject plainValue":
      rejects(TestTensor[FixtureReal[D], 4, tkVector, true], plainValue)
      rejects(TestTensor[FixtureReal[D], 4, tkMatrix, true], plainValue)
    test "vector and matrix proxies reject noSelection":
      rejects(TestTensor[FixtureReal[D], 4, tkVector, true], noSelection)
      rejects(TestTensor[FixtureReal[D], 4, tkMatrix, true], noSelection)
    test "vector and matrix proxies reject lostSpin":
      rejects(TestTensor[FixtureReal[D], 4, tkVector, true], lostSpin)
      rejects(TestTensor[FixtureReal[D], 4, tkMatrix, true], lostSpin)
