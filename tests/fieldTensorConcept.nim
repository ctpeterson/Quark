include support/tensorFixtures

include support/siteIndices

# Signature witnesses: component selection returns an access-qualified handle,
# while arithmetic returns an independent mathematical value.
type
  SiteDefect = enum
    siteValid, lostSpin, badShape, lostComponentMode, lostComponentIndex,
    plainComponent, missingSelection, missingSiteArithmetic, badNestedSpin,
    nestedModeLoss
  TensorSite[T, I; M: static ViewMode; F: static SiteDefect = siteValid] = object
  TensorView[T; M: static ViewMode; F: static SiteDefect] = object
  TensorField[T; F: static SiteDefect = siteValid] = object

template siteType[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): typedesc = T
template indexType[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): typedesc = I
template mode[T, I, M, F](p: TensorSite[T, I, M, F]): ViewMode = M
template tensorKind[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): TensorKind = T.tensorKind
template componentType[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): typedesc = T.componentType
template isSpin[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): bool =
  when F == lostSpin: false
  else: T.isSpin
template len[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): int =
  when F == badShape: T.len + 1
  else: T.len
template nrows[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): int = T.nrows
template ncols[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): int =
  when F == badShape: T.ncols + 1
  else: T.ncols
template precision[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): Precision = T.precision
template numericKind[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): NumericKind = T.numericKind
template realType[T, I, M, F](P: typedesc[TensorSite[T, I, M, F]]): typedesc = T.realType

template requireRead(M, F: untyped) =
  when M == WriteDiscard or F == missingSiteArithmetic:
    {.error: "unavailable site arithmetic".}

func re[T, I, M, F](p: TensorSite[T, I, M, F]): auto =
  requireRead(M, F)
  re(default(T))
func im[T, I, M, F](p: TensorSite[T, I, M, F]): auto =
  requireRead(M, F)
  im(default(T))

template siteUnary(symbol: untyped) =
  func symbol[T, I, M, F](p: TensorSite[T, I, M, F]): auto =
    requireRead(M, F)
    symbol(default(T))
template siteBinary(symbol: untyped) =
  func symbol[T, I, M, F](a, b: TensorSite[T, I, M, F]): auto =
    requireRead(M, F)
    symbol(default(T), default(T))
siteUnary(`+`)
siteUnary(`-`)
siteBinary(`+`)
siteBinary(`-`)
siteBinary(`*`)
siteBinary(`/`)
siteBinary(`div`)
siteBinary(`mod`)

func `*`[T, I, M, F; Scalar](p: TensorSite[T, I, M, F]; s: Scalar): auto =
  requireRead(M, F)
  default(T) * s
func `*`[T, I, M, F; Scalar](s: Scalar; p: TensorSite[T, I, M, F]): auto =
  requireRead(M, F)
  s * default(T)

template selectedComponent(T, I, M, F: untyped): untyped =
  when F == missingSelection: {.error: "unavailable component selection".}
  elif F == plainComponent: default(T.componentType)
  elif F == lostComponentMode: TensorSite[T.componentType, I, Read]()
  elif F == lostComponentIndex:
    when I is ScalarIndex: TensorSite[T.componentType, PackedIndex, M]()
    else: TensorSite[T.componentType, ScalarIndex, M]()
  elif F == badNestedSpin: TensorSite[T.componentType, I, M, lostSpin]()
  elif F == nestedModeLoss: TensorSite[T.componentType, I, M, lostComponentMode]()
  else: TensorSite[T.componentType, I, M]()

func `[]`[T, I, M, F](p: TensorSite[T, I, M, F]; i: int): auto =
  when T.tensorKind != tkVector: {.error: "vector indexing required".}
  selectedComponent(T, I, M, F)
func `[]`[T, I, M, F](p: TensorSite[T, I, M, F]; i, j: int): auto =
  when T.tensorKind != tkMatrix: {.error: "matrix indexing required".}
  selectedComponent(T, I, M, F)
func `:=`[T, I, M, F](p: TensorSite[T, I, M, F]; value: T) =
  when M == Read: {.error: "read-only site".}

template siteType[T, F](P: typedesc[TensorField[T, F]]): typedesc = T
template siteType[T, M, F](P: typedesc[TensorView[T, M, F]]): typedesc = T
template mode[T, M, F](v: TensorView[T, M, F]): ViewMode = M
func lattice[T, F](f: TensorField[T, F]): auto = newLattice([8, 8])
func lattice[T, M, F](v: TensorView[T, M, F]): auto = newLattice([8, 8])
func view[T, F](f: TensorField[T, F]; mode: static ViewMode): auto = TensorView[T, mode, F]()
func `[]`[T, M, F; I: ScalarIndex | PackedIndex](v: TensorView[T, M, F]; i: I): auto =
  TensorSite[T, I, M, F]()

static:
  type
    ColourVector = Vec[Complex[D], 3]
    ColourMatrix = Mat[Complex[D], 3, 3]
    Fermion = Vec[ColourVector, 4, true]
    Propagator = Mat[ColourMatrix, 4, 4, true]

  template checkSite(T, I: typedesc; M: static ViewMode) =
    doAssert TensorSite[T, I, M] is FieldSiteProxy[T, I]
  template checkType(T: typedesc) =
    checkSite(T, ScalarIndex, Read)
    checkSite(T, ScalarIndex, ReadWrite)
    checkSite(T, ScalarIndex, WriteDiscard)
    checkSite(T, PackedIndex, Read)
    checkSite(T, PackedIndex, ReadWrite)
    checkSite(T, PackedIndex, WriteDiscard)
    doAssert TensorField[T] is FieldObject[T]
  checkType(Vec[Integer[S], 3])
  checkType(Vec[Real[D], 3])
  checkType(Mat[Complex[D], 3, 3])
  checkType(Fermion)
  checkType(Propagator)
  checkType(Vec[Propagator, 2])

  template rejectSite(T: typedesc; flaw: static SiteDefect; M: static ViewMode) =
    doAssert not (TensorSite[T, ScalarIndex, M, flaw] is FieldSiteProxy[T, ScalarIndex])
    doAssert not (TensorSite[T, PackedIndex, M, flaw] is FieldSiteProxy[T, PackedIndex])
  template rejectModes(T: typedesc; flaw: static SiteDefect) =
    rejectSite(T, flaw, Read)
    rejectSite(T, flaw, ReadWrite)
    rejectSite(T, flaw, WriteDiscard)
  template rejectTensor(T: typedesc) =
    rejectModes(T, lostSpin)
    rejectModes(T, badShape)
    rejectModes(T, lostComponentIndex)
    rejectModes(T, plainComponent)
    rejectModes(T, missingSelection)
    rejectSite(T, lostComponentMode, ReadWrite)
    rejectSite(T, lostComponentMode, WriteDiscard)
    rejectSite(T, nestedModeLoss, ReadWrite)
    rejectSite(T, nestedModeLoss, WriteDiscard)
    rejectSite(T, missingSiteArithmetic, Read)
    rejectSite(T, missingSiteArithmetic, ReadWrite)
    doAssert TensorSite[T, ScalarIndex, WriteDiscard, missingSiteArithmetic] is FieldSiteProxy[T, ScalarIndex]
    doAssert not (TensorField[T, lostComponentIndex] is FieldObject[T])
  rejectTensor(Fermion)
  rejectTensor(Propagator)
  rejectModes(Vec[Fermion, 2], badNestedSpin)
  rejectModes(Mat[Propagator, 2, 2], badNestedSpin)

  type PackedOutput = TensorSite[Fermion, PackedIndex, WriteDiscard]
  doAssert typeof(default(PackedOutput)[0][0]) is FieldSiteProxy[Complex[D], PackedIndex]
  doAssert default(PackedOutput)[0][0].mode == WriteDiscard
  doAssert compiles(default(PackedOutput)[0][0] := default(Complex[D]))
  doAssert not compiles(+default(PackedOutput)[0][0])
  doAssert not compiles(default(TensorSite[Fermion, ScalarIndex, Read])[0][0] := default(Complex[D]))
  doAssert typeof(+default(TensorSite[Fermion, PackedIndex, Read])) isnot TensorSite[Fermion, PackedIndex, Read]

  # Tensor wrappers may forward numeric metadata; shape still selects the algebra.
  type ForwardedTensor = Vec[ColourVector, 5, true]
  template precision(V: typedesc[ForwardedTensor]): Precision = D
  template numericKind(V: typedesc[ForwardedTensor]): NumericKind = nkComplex
  doAssert ForwardedTensor.precision == D
  doAssert ForwardedTensor.numericKind == nkComplex
  checkSite(ForwardedTensor, ScalarIndex, Read)
  rejectSite(ForwardedTensor, badShape, Read)
