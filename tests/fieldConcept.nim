import quark

include support/siteIndices

# Independent structural fixtures have no newField constructor. Classification
# must not demand construction, nor confuse concept parameters with the matched
# concrete type. These are not ownership or native storage implementations.
type
  Defect = enum
    valid, missingLattice, wrongSiteType, missingPackedAccess,
    wrongIndexType, wrongProxySiteType, wrongViewMode, wrongProxyMode,
    runtimeMode, missingBinaryArithmetic, wrongResultKind, wrongPrecision
  FixtureReal[P: static Precision] = object
  FixtureLattice = typeof(newLattice([8, 8]))
  FixtureField[T; D: static Defect] = object
  FixtureView[T; D: static Defect; M: static ViewMode] = object
    runtimeAccess: ViewMode
  FixtureSite[T, S; D: static Defect; M: static ViewMode] = object

template precision[P](T: typedesc[FixtureReal[P]]): Precision = P
template numericKind[P](T: typedesc[FixtureReal[P]]): NumericKind = nkReal

template precision[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): Precision =
  when D == wrongPrecision: H
  else: T.precision
template numericKind[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): NumericKind = nkReal

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

template siteType[T; D](F: typedesc[FixtureField[T, D]]): typedesc =
  when D == wrongSiteType: int
  else: T

template siteType[T; D, M](V: typedesc[FixtureView[T, D, M]]): typedesc = T

template siteType[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): typedesc =
  when D == wrongProxySiteType: int
  else: T

template indexType[T, S; D, M](P: typedesc[FixtureSite[T, S, D, M]]): typedesc =
  when D == wrongIndexType: int
  else: S

func lattice[T; D](f: FixtureField[T, D]): auto =
  when D == missingLattice: 0
  else: newLattice([8, 8])

func lattice[T; D, M](v: FixtureView[T, D, M]): FixtureLattice =
  newLattice([8, 8])

template mode[T; D, M](v: FixtureView[T, D, M]): ViewMode =
  when D == runtimeMode: v.runtimeAccess
  else: M

template mode[T, S; D, M](p: FixtureSite[T, S, D, M]): ViewMode =
  when D == wrongProxyMode: Read
  else: M

func view[T; D](f: FixtureField[T, D]; access: static ViewMode): auto =
  when D == wrongViewMode: FixtureView[T, D, Read]()
  else: FixtureView[T, D, access]()

func `[]`[T; D, M](v: FixtureView[T, D, M]; s: ScalarIndex): auto =
  FixtureSite[T, ScalarIndex, D, M]()

func `[]`[T; D, M](v: FixtureView[T, D, M]; s: PackedIndex): auto =
  when D == missingPackedAccess: 0
  else: FixtureSite[T, PackedIndex, D, M]()

static:
  doAssert FixtureField[FixtureReal[D], valid] is FieldObject[FixtureReal[D]]
  doAssert FixtureField[FixtureReal[S], valid] is FieldObject[FixtureReal[S]]
  doAssert not (FixtureField[FixtureReal[S], valid] is FieldObject[FixtureReal[D]])
  doAssert not compiles(FixtureField[FixtureReal[D], valid].newField(newLattice([8, 8])))
  doAssert not (FixtureField[FixtureReal[D], missingLattice] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], wrongSiteType] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], missingPackedAccess] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], wrongIndexType] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], wrongProxySiteType] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], wrongViewMode] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], wrongProxyMode] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], runtimeMode] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], missingBinaryArithmetic] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], wrongResultKind] is FieldObject[FixtureReal[D]])
  doAssert not (FixtureField[FixtureReal[D], wrongPrecision] is FieldObject[FixtureReal[D]])
  # WriteDiscard classification does not demand readable arithmetic.
  doAssert FixtureSite[FixtureReal[D], ScalarIndex, missingBinaryArithmetic, WriteDiscard] is FieldSiteProxy[FixtureReal[D], ScalarIndex]
  doAssert not (FixtureSite[string, ScalarIndex, valid, WriteDiscard] is FieldSiteProxy[string, ScalarIndex])
