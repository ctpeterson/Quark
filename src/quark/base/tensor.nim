#[
Tensor conformance

src: quark/base/tensor.nim
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

## Vector, square-matrix, and Spin capability contracts
## ====================================================
##
## This module describes the mathematical structure and readable algebra of
## one tensor level. A component may itself be numeric, a vector, or a square
## matrix, so the same contracts describe nested tensors without flattening
## independent mathematical index spaces.
##
## ``VectorObject[T, N]`` requires a positive static length ``N``, vector
## ``tensorKind``, and ``componentType`` equal to ``T``. ``MatrixObject[T, N]``
## requires square shape: both static ``nrows`` and ``ncols`` equal ``N``.
## Components must recursively satisfy the supported numeric or tensor structure.
## Shape classification does not require readable elements, which permits
## structural checks on write-only Field components.
##
## ``VectorArithmetic[T, N]`` adds readable component selection, unary signs,
## addition and subtraction, and multiplication on either side by a numeric
## leaf value. ``MatrixArithmetic[T, N]`` additionally requires same-type
## matrix multiplication. Arithmetic results preserve shape and mathematical
## component structure without requiring the same concrete result type.
## Products between different tensor types, including matrix-vector products,
## require additional operand-pair conformance; they are not established by
## classifying each operand independently.
##
## ``SpinObject[T]`` identifies a Spin-tagged tensor with ``T``'s shape and
## component structure. Only Spin types must expose the static boolean
## ``isSpin = true``. Ordinary tensors need no tag or marker object. Arithmetic
## and recursive component reads preserve Spin identity wherever it is present.
## A Spin component may be another tensor rather than a numeric leaf.
##
## Tensor indices select mathematical components. They do not choose lattice
## sites or packing lanes: those choices belong to Site Indices and iteration
## spaces. Field component access additionally preserves access mode, lifetime,
## and Lattice provenance through the Field contracts.
##
## These are capability concepts, not concrete Vector, Matrix, or Spin storage
## implementations. Adapters supply representations and connect operations to
## existing backend tensor facilities. Structural conformance does not by itself
## prove numerical contraction, writable access, or compatibility with a
## particular physics operator. No matrix-division operation is implied by
## numeric division at its component leaves.


import numeric

func isComponent[T](_: typedesc[T]): bool {.compileTime.}

func componentArithmetic[V,T](
  _: typedesc[V];
  expected: typedesc[T]
): bool {.compileTime.}

func leaf[T](_: typedesc[T]): auto {.compileTime.} =
  return when compiles(T.componentType): leaf(T.componentType) else: default(T)

func preservesSpin[V,S](value: typedesc[V]; source: typedesc[S]): bool {.compileTime.}

template vectorResult(Value, T: typedesc; N: static int; Source: typedesc): bool =
  (Value is VectorObject[T,N]) and preservesSpin(Value, Source)

template matrixResult(Value, T: typedesc; N: static int; Source: typedesc): bool =
  (Value is MatrixObject[T,N]) and preservesSpin(Value, Source)

type
  TensorKind* = enum
    ## The vector or matrix structure of one tensor level.
    tkVector
    tkMatrix

type
  VectorObject*[T; N: static int] = concept vector, type V
    ## Vector structure with N components of mathematical type T.
    ## Classification requires static shape and component metadata, not reads.
    N > 0

    V.componentType is T
    const kind = V.tensorKind
    kind == tkVector

    const size = V.len
    size is int
    size == N

    isComponent(T)

  MatrixObject*[T; N: static int] = concept matrix, type M
    ## Square matrix structure with N rows and columns of mathematical type T.
    ## Classification requires static shape and component metadata, not reads.
    N > 0

    M.componentType is T
    const kind = M.tensorKind
    kind == tkMatrix

    const rows = M.nrows
    const cols = M.ncols
    rows is int
    cols is int
    rows == N
    cols == N

    isComponent(T)

type
  VectorArithmetic*[T; N: static int] = concept vector, other, type V
    ## Readable vector components, additive arithmetic, and numeric scaling.
    ## Results preserve shape and any Spin identity without requiring concrete-type closure.
    V is VectorObject[T,N]

    mixin `[]`, `+`, `-`, `*`
    componentArithmetic(typeof(vector[0]), T)

    vectorResult(typeof(+vector), T, N, V)
    vectorResult(typeof(-vector), T, N, V)
    vectorResult(typeof(vector + other), T, N, V)
    vectorResult(typeof(vector - other), T, N, V)
    vectorResult(typeof(vector * default(typeof(leaf(T)))), T, N, V)
    vectorResult(typeof(default(typeof(leaf(T))) * vector), T, N, V)

  MatrixArithmetic*[T; N: static int] = concept matrix, other, type M
    ## Readable matrix components, additive arithmetic, and numeric scaling.
    ## Same-type multiplication preserves square shape. Products with different
    ## operand types require separate conformance checks.
    M is MatrixObject[T,N]

    mixin `[]`, `+`, `-`, `*`
    componentArithmetic(typeof(matrix[0, 0]), T)

    matrixResult(typeof(+matrix), T, N, M)
    matrixResult(typeof(-matrix), T, N, M)
    matrixResult(typeof(matrix + other), T, N, M)
    matrixResult(typeof(matrix - other), T, N, M)
    matrixResult(typeof(matrix * default(typeof(leaf(T)))), T, N, M)
    matrixResult(typeof(default(typeof(leaf(T))) * matrix), T, N, M)
    matrixResult(typeof(matrix * other), T, N, M)

  SpinObject*[T] = concept spin, type S
    ## Spin-tagged vector or matrix retaining T's shape and component structure.
    ## T describes the wrapped mathematical tensor; no concrete wrapper is required.
    ## Only spin types must expose the compile-time boolean isSpin = true.
    type Element = T.componentType
    const spinIdentity = S.isSpin
    spinIdentity is bool
    spinIdentity == true

    when compiles(T.tensorKind) and T.tensorKind == tkVector:
      const length = T.len
      T is VectorObject[Element, length]
      S is VectorObject[T.componentType, T.len]
    elif compiles(T.tensorKind) and T.tensorKind == tkMatrix:
      const dimension = T.nrows
      T is MatrixObject[Element, dimension]
      S is MatrixObject[T.componentType, T.nrows]
    else: false

# Generic helpers keep recursive component matching below Nim's concept depth limit
func isComponent[T](_: typedesc[T]): bool {.compileTime.} =
  when compiles(T.tensorKind):
    return when T.tensorKind == tkVector: T is VectorObject[T.componentType, T.len]
    elif T.tensorKind == tkMatrix: T is MatrixObject[T.componentType, T.nrows]
    else: false
  elif compiles(T.precision):
    const prec = T.precision
    return T is Numeric[prec]
  else: return false

func componentArithmetic[V,T](
  _: typedesc[V];
  expected: typedesc[T]
): bool {.compileTime.} =
  when compiles(T.tensorKind):
    return when T.tensorKind == tkVector:
      (V is VectorArithmetic[T.componentType, T.len]) and preservesSpin(V, T)
    elif T.tensorKind == tkMatrix:
      (V is MatrixArithmetic[T.componentType, T.nrows]) and preservesSpin(V, T)
    else: false
  elif compiles(T.precision):
    const prec = T.precision
    return when T is IntegerNumber[prec]: V is IntegerArithmetic[prec]
    elif T is RealNumber[prec]: V is RealArithmetic[prec]
    elif T is ComplexNumber[prec]: V is ComplexArithmetic[prec]
    else: false
  else: return false

func preservesSpin[V,S](value: typedesc[V]; source: typedesc[S]): bool {.compileTime.} =
  return when S is SpinObject[S]: V is SpinObject[S] else: true

when isMainModule:
  import std/unittest

  # Arithmetic signatures only; there is deliberately no numeric storage here.
  type
    TestNumber[P: static Precision; K: static NumericKind] = object
    Real[P: static Precision] = TestNumber[P, nkReal]
    Integer[P: static Precision] = TestNumber[P, nkInteger]
    Complex[P: static Precision] = TestNumber[P, nkComplex]
  template precision[P, K](T: typedesc[TestNumber[P, K]]): Precision = P
  template numericKind[P, K](T: typedesc[TestNumber[P, K]]): NumericKind = K
  template realType[P, K](T: typedesc[TestNumber[P, K]]): typedesc = Real[P]
  func re[P, K](v: TestNumber[P, K]): Real[P] = Real[P]()
  func im[P, K](v: TestNumber[P, K]): Real[P] = Real[P]()
  func `+`[P, K](v: TestNumber[P, K]): TestNumber[P, K] = TestNumber[P, K]()
  func `-`[P, K](v: TestNumber[P, K]): TestNumber[P, K] = TestNumber[P, K]()
  template numericOperation(symbol: untyped) =
    func symbol[P, K](a, b: TestNumber[P, K]): TestNumber[P, K] = TestNumber[P, K]()
  numericOperation(`+`)
  numericOperation(`-`)
  numericOperation(`*`)
  numericOperation(`/`)
  numericOperation(`div`)
  numericOperation(`mod`)

  # Independent conformance witnesses, not tensor storage or numerical kernels.
  type
    Defect = enum
      valid, writeOnly, runtimeShape, missingArithmetic, wrongResultShape,
      wrongResultSpin, wrongComponent, missingScale, missingProduct, expressionSource, wrongNestedSpin, missingLeftScale, missingRightScale
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
    when F in {missingScale, missingRightScale}: {.error: "unavailable scaling".}
    default(operationResult(typeof(v)))
  func `*`[T, N, Spin, F; Scalar](s: Scalar; v: Vec[T, N, Spin, F]): auto =
    when F in {missingScale, missingLeftScale}: {.error: "unavailable scaling".}
    default(operationResult(typeof(v)))
  func `*`[T, R, C, Spin, F; Scalar](m: Mat[T, R, C, Spin, F]; s: Scalar): auto =
    when F in {missingScale, missingRightScale}: {.error: "unavailable scaling".}
    default(operationResult(typeof(m)))
  func `*`[T, R, C, Spin, F; Scalar](s: Scalar; m: Mat[T, R, C, Spin, F]): auto =
    when F in {missingScale, missingLeftScale}: {.error: "unavailable scaling".}
    default(operationResult(typeof(m)))
  func `*`[T, R, C, Spin, F](a, b: Mat[T, R, C, Spin, F]): auto =
    when F == missingProduct: {.error: "unavailable multiplication".}
    default(operationResult(typeof(a)))

  suite "tensor structure":
    test "positive vector shapes classify without readable components":
      check Vec[Real[D], 1] is VectorObject[Real[D], 1]
      check Vec[Real[D], 3, false, writeOnly] is VectorObject[Real[D], 3]
      check Vec[Real[D], 3, false, writeOnly] isnot VectorArithmetic[Real[D], 3]

    test "square matrix structure does not require readable components":
      check Mat[Real[D], 1, 1] is MatrixObject[Real[D], 1]
      check Mat[Real[D], 3, 3, false, writeOnly] is MatrixObject[Real[D], 3]
      check Mat[Real[D], 3, 3, false, writeOnly] isnot MatrixArithmetic[Real[D], 3]

    test "zero and negative vector dimensions reject":
      check Vec[Real[D], 0] isnot VectorObject[Real[D], 0]
      check Vec[Real[D], -1] isnot VectorObject[Real[D], -1]

    test "zero and negative matrix dimensions reject":
      check Mat[Real[D], 0, 0] isnot MatrixObject[Real[D], 0]
      check Mat[Real[D], -1, -1] isnot MatrixObject[Real[D], -1]

    test "rectangular matrices reject square classification":
      check Mat[Real[D], 2, 3] isnot MatrixObject[Real[D], 2]
      check Mat[Real[D], 2, 3] isnot MatrixObject[Real[D], 3]

    test "expected shape must agree with type metadata":
      check Vec[Real[D], 3] isnot VectorObject[Real[D], 4]
      check Mat[Real[D], 3, 3] isnot MatrixObject[Real[D], 4]

    test "matrix len does not make it a vector":
      check Mat[Real[D], 3, 3] isnot VectorObject[Real[D], 3]
      check Vec[Real[D], 3] isnot MatrixObject[Real[D], 3]

    test "runtime shapes reject":
      check Vec[Real[D], 3, false, runtimeShape] isnot VectorObject[Real[D], 3]
      check Mat[Real[D], 3, 3, false, runtimeShape] isnot MatrixObject[Real[D], 3]

    test "component precision is part of tensor structure":
      check Vec[Real[S], 3] isnot VectorObject[Real[D], 3]
      check Mat[Real[S], 3, 3] isnot MatrixObject[Real[D], 3]

    test "unsupported components reject":
      check Vec[string, 3] isnot VectorObject[string, 3]
      check Mat[int, 3, 3] isnot MatrixObject[int, 3]
      static: doAssert not isComponent(string)

    test "invalid nested structure rejects recursively":
      type BadVector = Vec[Real[D], 0]
      type BadMatrix = Mat[Real[D], 2, 3]
      check Vec[BadVector, 4] isnot VectorObject[BadVector, 4]
      check Mat[BadMatrix, 4, 4] isnot MatrixObject[BadMatrix, 4]

  suite "tensor arithmetic":
    test "vector and matrix arithmetic accept Integer H components":
      check Vec[Integer[H], 3] is VectorArithmetic[Integer[H], 3]
      check Mat[Integer[H], 3, 3] is MatrixArithmetic[Integer[H], 3]
    test "vector and matrix arithmetic accept Integer S components":
      check Vec[Integer[S], 3] is VectorArithmetic[Integer[S], 3]
      check Mat[Integer[S], 3, 3] is MatrixArithmetic[Integer[S], 3]
    test "vector and matrix arithmetic accept Integer D components":
      check Vec[Integer[D], 3] is VectorArithmetic[Integer[D], 3]
      check Mat[Integer[D], 3, 3] is MatrixArithmetic[Integer[D], 3]
    test "vector and matrix arithmetic accept Complex H components":
      check Vec[Complex[H], 3] is VectorArithmetic[Complex[H], 3]
      check Mat[Complex[H], 3, 3] is MatrixArithmetic[Complex[H], 3]
    test "vector and matrix arithmetic accept Complex S components":
      check Vec[Complex[S], 3] is VectorArithmetic[Complex[S], 3]
      check Mat[Complex[S], 3, 3] is MatrixArithmetic[Complex[S], 3]
    test "vector and matrix arithmetic accept Complex D components":
      check Vec[Complex[D], 3] is VectorArithmetic[Complex[D], 3]
      check Mat[Complex[D], 3, 3] is MatrixArithmetic[Complex[D], 3]
    test "vector and matrix arithmetic accept H components":
      check Vec[Real[H], 3] is VectorArithmetic[Real[H], 3]
      check Mat[Real[H], 3, 3] is MatrixArithmetic[Real[H], 3]
    test "vector and matrix arithmetic accept S components":
      check Vec[Real[S], 3] is VectorArithmetic[Real[S], 3]
      check Mat[Real[S], 3, 3] is MatrixArithmetic[Real[S], 3]
    test "vector and matrix arithmetic accept D components":
      check Vec[Real[D], 3] is VectorArithmetic[Real[D], 3]
      check Mat[Real[D], 3, 3] is MatrixArithmetic[Real[D], 3]
    test "vector and matrix arithmetic reject missingArithmetic":
      check Vec[Real[D], 3, false, missingArithmetic] isnot VectorArithmetic[Real[D], 3]
      check Mat[Real[D], 3, 3, false, missingArithmetic] isnot MatrixArithmetic[Real[D], 3]
    test "vector and matrix arithmetic reject wrongResultShape":
      check Vec[Real[D], 3, false, wrongResultShape] isnot VectorArithmetic[Real[D], 3]
      check Mat[Real[D], 3, 3, false, wrongResultShape] isnot MatrixArithmetic[Real[D], 3]
    test "vector and matrix arithmetic reject wrongComponent":
      check Vec[Real[D], 3, false, wrongComponent] isnot VectorArithmetic[Real[D], 3]
      check Mat[Real[D], 3, 3, false, wrongComponent] isnot MatrixArithmetic[Real[D], 3]
    test "vector and matrix arithmetic reject missingScale":
      check Vec[Real[D], 3, false, missingScale] isnot VectorArithmetic[Real[D], 3]
      check Mat[Real[D], 3, 3, false, missingScale] isnot MatrixArithmetic[Real[D], 3]
    test "vector and matrix arithmetic reject missingLeftScale":
      check Vec[Real[D], 3, false, missingLeftScale] isnot VectorArithmetic[Real[D], 3]
      check Mat[Real[D], 3, 3, false, missingLeftScale] isnot MatrixArithmetic[Real[D], 3]
    test "vector and matrix arithmetic reject missingRightScale":
      check Vec[Real[D], 3, false, missingRightScale] isnot VectorArithmetic[Real[D], 3]
      check Mat[Real[D], 3, 3, false, missingRightScale] isnot MatrixArithmetic[Real[D], 3]
    test "square matrix multiplication is independently required":
      check Mat[Real[D], 3, 3, false, missingProduct] is MatrixObject[Real[D], 3]
      check Mat[Real[D], 3, 3, false, missingProduct] isnot MatrixArithmetic[Real[D], 3]

    test "expression results need not have the operand's concrete type":
      type V = Vec[Real[D], 3, false, expressionSource]
      type M = Mat[Real[D], 3, 3, false, expressionSource]
      check typeof(+default(V)) isnot V
      check typeof(+default(M)) isnot M
      check V is VectorArithmetic[Real[D], 3]
      check M is MatrixArithmetic[Real[D], 3]

    test "nested vector components remain readable":
      type Inner = Vec[Real[D], 3]
      check Vec[Inner, 4] is VectorArithmetic[Inner, 4]
      check Mat[Inner, 4, 4] is MatrixArithmetic[Inner, 4]

    test "nested matrix components remain readable":
      type Inner = Mat[Real[D], 3, 3]
      check Vec[Inner, 4] is VectorArithmetic[Inner, 4]
      check Mat[Inner, 4, 4] is MatrixArithmetic[Inner, 4]

    test "write-only nested components reject readable arithmetic":
      type Inner = Vec[Real[D], 3, false, writeOnly]
      check Vec[Inner, 4] is VectorObject[Inner, 4]
      check Vec[Inner, 4] isnot VectorArithmetic[Inner, 4]

    test "leaf discovery traverses multiple tensor levels":
      type Nested = Vec[Mat[Vec[Real[S], 3], 2, 2], 4]
      check typeof(leaf(Nested)) is Real[S]
      check typeof(leaf(Real[D])) is Real[D]
      static: doAssert isComponent(Nested)

  suite "spin identity":
    test "ordinary tensors do not need an isSpin declaration":
      check not compiles(Vec[Real[D], 3].isSpin)
      check Vec[Real[D], 3] isnot SpinObject[Vec[Real[D], 3]]
      check Vec[Real[D], 3] is VectorArithmetic[Real[D], 3]

    test "spin vectors and matrices preserve mathematical shape":
      check Vec[Real[D], 4, true] is SpinObject[Vec[Real[D], 4]]
      check Mat[Real[D], 4, 4, true] is SpinObject[Mat[Real[D], 4, 4]]

    test "spin cannot hide shape or component mismatch":
      check Vec[Real[D], 4, true] isnot SpinObject[Vec[Real[D], 3]]
      check Mat[Real[D], 4, 4, true] isnot SpinObject[Mat[Real[S], 4, 4]]
      check Vec[Real[D], 4, true] isnot SpinObject[Mat[Real[D], 4, 4]]

    test "spin does not classify a scalar":
      check Real[D] isnot SpinObject[Real[D]]

    test "arithmetic must retain a source spin tag":
      check Vec[Real[D], 4, true, wrongResultSpin] isnot VectorArithmetic[Real[D], 4]
      check Mat[Real[D], 4, 4, true, wrongResultSpin] isnot MatrixArithmetic[Real[D], 4]
      check Vec[Real[D], 4, true] is VectorArithmetic[Real[D], 4]
      check Mat[Real[D], 4, 4, true] is MatrixArithmetic[Real[D], 4]

    test "component reads must preserve nested spin":
      type Inner = Vec[Real[D], 4, true]
      check Vec[Inner, 2] is VectorArithmetic[Inner, 2]
      check Vec[Inner, 2, false, wrongNestedSpin] isnot VectorArithmetic[Inner, 2]

    test "spin preservation is required only when present on the source":
      static: doAssert preservesSpin(Vec[Real[D], 4, true], Vec[Real[D], 4])
      static: doAssert not preservesSpin(Vec[Real[D], 4], Vec[Real[D], 4, true])
