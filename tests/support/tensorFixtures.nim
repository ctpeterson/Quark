import quark

# Independent conformance witnesses, not tensor storage or numerical kernels.
type
  Defect = enum
    valid, writeOnly, runtimeShape, missingArithmetic, wrongResultShape,
    wrongResultSpin, wrongComponent, missingScale, missingProduct, expressionSource, wrongNestedSpin
  Vec[T; N: static int; Spin: static bool = false; F: static Defect = valid] = object
  Mat[T; R, C: static int; Spin: static bool = false; F: static Defect = valid] = object
  NumericRef[T] = object
  TensorFixture = Vec | Mat

var runtimeLength = 3

template tensorKind[T, N, Spin, F](V: typedesc[Vec[T, N, Spin, F]]): TensorKind = tkVector
template tensorKind[T, R, C, Spin, F](M: typedesc[Mat[T, R, C, Spin, F]]): TensorKind = tkMatrix
# Matrix APIs may also expose len; this must not classify them as vectors.
template len[T, R, C, Spin, F](M: typedesc[Mat[T, R, C, Spin, F]]): int = R

template componentType[T, N, Spin, F](V: typedesc[Vec[T, N, Spin, F]]): typedesc = T
template componentType[T, R, C, Spin, F](M: typedesc[Mat[T, R, C, Spin, F]]): typedesc = T
template isSpin[T, N, F](V: typedesc[Vec[T, N, true, F]]): bool = true
template isSpin[T, R, C, F](M: typedesc[Mat[T, R, C, true, F]]): bool = true
template len[T, N, Spin, F](V: typedesc[Vec[T, N, Spin, F]]): int =
  when F == runtimeShape: runtimeLength
  else: N
template nrows[T, R, C, Spin, F](M: typedesc[Mat[T, R, C, Spin, F]]): int =
  when F == runtimeShape: runtimeLength
  else: R
template ncols[T, R, C, Spin, F](M: typedesc[Mat[T, R, C, Spin, F]]): int = C

template precision[T](V: typedesc[NumericRef[T]]): Precision = T.precision
template numericKind[T](V: typedesc[NumericRef[T]]): NumericKind = T.numericKind
template realType[T](V: typedesc[NumericRef[T]]): typedesc = T.realType
func re[T](v: NumericRef[T]): T.realType = default(T.realType)
func im[T](v: NumericRef[T]): T.realType = default(T.realType)

template numericUnary(symbol: untyped) =
  func symbol[ValueType](v: NumericRef[ValueType]): auto = symbol(default(ValueType))
template numericBinary(symbol: untyped) =
  func symbol[ValueType](a, b: NumericRef[ValueType]): auto =
    symbol(default(ValueType), default(ValueType))
numericUnary(`+`)
numericUnary(`-`)
numericBinary(`+`)
numericBinary(`-`)
numericBinary(`*`)
numericBinary(`/`)
numericBinary(`div`)
numericBinary(`mod`)

template component(T: typedesc): untyped =
  when compiles(T.precision): NumericRef[T]()
  else: default(T)

func `[]`[T, N, Spin, F](v: Vec[T, N, Spin, F]; i: int): auto =
  when F == writeOnly: {.error: "write-only vector".}
  when F == wrongComponent: NumericRef[Real[S]]()
  elif F == wrongNestedSpin: Vec[T.componentType, T.len, false]()
  else: component(T)
func `[]`[T, R, C, Spin, F](m: Mat[T, R, C, Spin, F]; i, j: int): auto =
  when F == writeOnly: {.error: "write-only matrix".}
  when F == wrongComponent: NumericRef[Real[S]]()
  else: component(T)

template operationResult[T, N, Spin, F](V: typedesc[Vec[T, N, Spin, F]]): typedesc =
  when F == writeOnly or F == missingArithmetic: {.error: "unavailable arithmetic".}
  elif F == wrongResultShape: Vec[T, N + 1, Spin]
  elif F == wrongResultSpin: Vec[T, N, false]
  else: Vec[T, N, Spin]
template operationResult[T, R, C, Spin, F](M: typedesc[Mat[T, R, C, Spin, F]]): typedesc =
  when F == writeOnly or F == missingArithmetic: {.error: "unavailable arithmetic".}
  elif F == wrongResultShape: Mat[T, R, C + 1, Spin]
  elif F == wrongResultSpin: Mat[T, R, C, false]
  else: Mat[T, R, C, Spin]

template tensorUnary(symbol: untyped) =
  func symbol[ValueType: TensorFixture](v: ValueType): auto = default(operationResult(ValueType))
template tensorBinary(symbol: untyped) =
  func symbol[ValueType: TensorFixture](a, b: ValueType): auto = default(operationResult(ValueType))
tensorUnary(`+`)
tensorUnary(`-`)
tensorBinary(`+`)
tensorBinary(`-`)

func `*`[T, N, Spin, F; Scalar](v: Vec[T, N, Spin, F]; s: Scalar): auto =
  when F == missingScale: {.error: "unavailable scaling".}
  default(operationResult(typeof(v)))
func `*`[T, N, Spin, F; Scalar](s: Scalar; v: Vec[T, N, Spin, F]): auto =
  when F == missingScale: {.error: "unavailable scaling".}
  default(operationResult(typeof(v)))
func `*`[T, R, C, Spin, F; Scalar](m: Mat[T, R, C, Spin, F]; s: Scalar): auto =
  when F == missingScale: {.error: "unavailable scaling".}
  default(operationResult(typeof(m)))
func `*`[T, R, C, Spin, F; Scalar](s: Scalar; m: Mat[T, R, C, Spin, F]): auto =
  when F == missingScale: {.error: "unavailable scaling".}
  default(operationResult(typeof(m)))
func `*`[T, R, C, Spin, F](a, b: Mat[T, R, C, Spin, F]): auto =
  when F == missingProduct: {.error: "unavailable multiplication".}
  default(operationResult(typeof(a)))
