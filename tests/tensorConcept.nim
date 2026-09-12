include support/tensorFixtures

static:
  doAssert Vec[Real[D], 3] is VectorObject[Real[D], 3]
  doAssert Mat[Real[D], 3, 3] is MatrixObject[Real[D], 3]
  doAssert not (Mat[Real[D], 3, 3] is VectorObject[Real[D], 3])
  doAssert not (Vec[Real[D], 3] is MatrixObject[Real[D], 3])
  doAssert not (Vec[Real[D], 3] is VectorObject[Real[D], 4])
  doAssert not (Mat[Real[D], 3, 4] is MatrixObject[Real[D], 3])
  doAssert not (Mat[Real[D], 4, 3] is MatrixObject[Real[D], 3])
  doAssert not (Vec[Real[D], 0] is VectorObject[Real[D], 0])
  doAssert not (Mat[Real[D], 0, 0] is MatrixObject[Real[D], 0])
  doAssert not (Vec[Real[D], 3] is VectorObject[Real[S], 3])
  doAssert not (Vec[string, 3] is VectorObject[string, 3])
  doAssert not (Mat[string, 3, 3] is MatrixObject[string, 3])
  doAssert not (Vec[Real[D], 3, false, runtimeShape] is VectorObject[Real[D], 3])
  doAssert not (Mat[Real[D], 3, 3, false, runtimeShape] is MatrixObject[Real[D], 3])

  template checkNumeric(T: typedesc) =
    doAssert Vec[T, 3] is VectorArithmetic[T, 3]
    doAssert Mat[T, 3, 3] is MatrixArithmetic[T, 3]
  checkNumeric(Integer[S])
  checkNumeric(Real[D])
  checkNumeric(Complex[D])
  doAssert typeof(default(Vec[Real[D], 3])[0]) isnot Real[D]

  type
    ColourVector = Vec[Complex[D], 3]
    ColourMatrix = Mat[Complex[D], 3, 3]
    Fermion = Vec[ColourVector, 4, true]
    Propagator = Mat[ColourMatrix, 4, 4, true]
  doAssert Fermion is VectorObject[ColourVector, 4]
  doAssert Fermion is VectorArithmetic[ColourVector, 4]
  doAssert Propagator is MatrixArithmetic[ColourMatrix, 4]
  doAssert Fermion is SpinObject[Vec[ColourVector, 4]]
  doAssert Propagator is SpinObject[Mat[ColourMatrix, 4, 4]]
  doAssert not (ColourVector is SpinObject[Vec[Complex[D], 3]])
  doAssert not (Fermion is SpinObject[Vec[ColourVector, 2]])
  doAssert not (Fermion is SpinObject[Real[D]])
  doAssert not (Fermion is SpinObject[Mat[ColourVector, 4, 4]])

  template checkWriteOnly(T: typedesc; N: static int; Spin: static bool) =
    doAssert Vec[T, N, Spin, writeOnly] is VectorObject[T, N]
    doAssert Mat[T, N, N, Spin, writeOnly] is MatrixObject[T, N]
    doAssert not (Vec[T, N, Spin, writeOnly] is VectorArithmetic[T, N])
    doAssert not (Mat[T, N, N, Spin, writeOnly] is MatrixArithmetic[T, N])
  checkWriteOnly(Real[D], 3, false)
  checkWriteOnly(ColourVector, 4, true)
  doAssert Vec[ColourVector, 4, true, writeOnly] is SpinObject[Vec[ColourVector, 4]]

  template rejectArithmetic(flaw: static Defect) =
    doAssert not (Vec[Real[D], 3, true, flaw] is VectorArithmetic[Real[D], 3])
    doAssert not (Mat[Real[D], 3, 3, true, flaw] is MatrixArithmetic[Real[D], 3])
  rejectArithmetic(missingArithmetic)
  rejectArithmetic(wrongResultShape)
  rejectArithmetic(wrongResultSpin)
  rejectArithmetic(wrongComponent)
  rejectArithmetic(missingScale)
  doAssert not (Mat[Real[D], 3, 3, true, missingProduct] is MatrixArithmetic[Real[D], 3])
  type BadColour = Vec[Complex[D], 3, false, missingArithmetic]
  doAssert Vec[BadColour, 4, true] is VectorObject[BadColour, 4]
  doAssert not (Vec[BadColour, 4, true] is VectorArithmetic[BadColour, 4])

  type ExpressionInput = Vec[Real[D], 3, true, expressionSource]
  doAssert ExpressionInput is VectorArithmetic[Real[D], 3]
  doAssert typeof(+default(ExpressionInput)) isnot ExpressionInput
  doAssert typeof((default(ExpressionInput) + default(ExpressionInput)) * newReal(2.0)) is VectorArithmetic[Real[D], 3]
  # Three tensor levels also recurse without imposing numeric metadata on tensors.
  type DeepTensor = Vec[Propagator, 2]
  doAssert DeepTensor is VectorArithmetic[Propagator, 2]

  doAssert not (Vec[Fermion, 2, false, wrongNestedSpin] is VectorArithmetic[Fermion, 2])
  type
    PlainVector = object
    FalseSpin = object
    RuntimeSpin = object
    InvalidSpin = object
    IdentityFixture = PlainVector | FalseSpin | RuntimeSpin | InvalidSpin
  template tensorKind[V: IdentityFixture](_: typedesc[V]): TensorKind = tkVector
  template componentType[V: IdentityFixture](_: typedesc[V]): typedesc = Real[D]
  template len[V: IdentityFixture](_: typedesc[V]): int = 3
  template isSpin(V: typedesc[FalseSpin]): bool = false
  template isSpin(V: typedesc[RuntimeSpin]): bool = runtimeLength == 3
  template isSpin(V: typedesc[InvalidSpin]): string = "spin"
  doAssert FalseSpin is VectorObject[Real[D], 3]
  doAssert not (FalseSpin is SpinObject[PlainVector])
  doAssert not (RuntimeSpin is SpinObject[PlainVector])
  doAssert not (InvalidSpin is SpinObject[PlainVector])
  doAssert PlainVector is VectorObject[Real[D], 3]
  doAssert not (PlainVector is SpinObject[PlainVector])
  doAssert not compiles(Vec[Real[D], 3].isSpin)
  doAssert not compiles(Mat[Real[D], 3, 3].isSpin)
