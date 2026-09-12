import std/unittest

import quark

include support/siteIndices

type
  TestStoredReal[P: static Precision] = object
  TestRealExpression[P: static Precision] = object

template precision[P](T: typedesc[TestStoredReal[P]]): Precision =
  P

template precision[P](T: typedesc[TestRealExpression[P]]): Precision =
  P

template numericKind[P](T: typedesc[TestStoredReal[P]]): NumericKind =
  nkReal

template numericKind[P](T: typedesc[TestRealExpression[P]]): NumericKind =
  nkReal

template defineTestArithmetic(Number: untyped) =
  func `+`[P](value: Number[P]): TestRealExpression[P] =
    TestRealExpression[P]()

  func `-`[P](value: Number[P]): TestRealExpression[P] =
    TestRealExpression[P]()

  func `+`[P](lhs, rhs: Number[P]): TestRealExpression[P] =
    TestRealExpression[P]()

  func `-`[P](lhs, rhs: Number[P]): TestRealExpression[P] =
    TestRealExpression[P]()

  func `*`[P](lhs, rhs: Number[P]): TestRealExpression[P] =
    TestRealExpression[P]()

  func `/`[P](lhs, rhs: Number[P]): TestRealExpression[P] =
    TestRealExpression[P]()

defineTestArithmetic(TestStoredReal)
defineTestArithmetic(TestRealExpression)

func `*`[P](
  lhs: TestRealExpression[P]; rhs: TestStoredReal[P]
): TestRealExpression[P] =
  TestRealExpression[P]()

static:
  doAssert Integer[S] is IntegerNumber[S]
  doAssert Integer[D] is IntegerNumber[D]
  doAssert Real[S] is RealNumber[S]
  doAssert Real[D] is RealNumber[D]
  doAssert Complex[S] is ComplexNumber[S]
  doAssert Complex[D] is ComplexNumber[D]
  doAssert Integer[D] is IntegerArithmetic[D]
  doAssert Real[D] is RealArithmetic[D]
  doAssert Complex[D] is ComplexArithmetic[D]
  doAssert TestStoredReal[D] is RealArithmetic[D]
  doAssert TestRealExpression[D] is RealArithmetic[D]
  doAssert typeof(
    (default(TestStoredReal[D]) + default(TestStoredReal[D])) *
      default(TestStoredReal[D])
  ) is TestRealExpression[D]

  doAssert not (int32 is IntegerNumber[S])
  doAssert not (float64 is RealNumber[D])
  doAssert not (Integer[S] is RealNumber[S])
  doAssert not (Real[S] is RealNumber[D])
  doAssert not (Complex[S] is ComplexNumber[D])

  doAssert promotedPrecision(H, S) == S
  doAssert promotedPrecision(S, H) == S
  doAssert promotedPrecision(S, D) == D
  doAssert promotedPrecision(D, S) == D
  doAssert promotedPrecision(D, H) == D
  doAssert promotedPrecision(H, D) == D
  doAssert promotedKind(nkInteger, nkReal) == nkReal
  doAssert promotedKind(nkReal, nkInteger) == nkReal
  doAssert promotedKind(nkReal, nkComplex) == nkComplex
  doAssert promotedKind(nkComplex, nkReal) == nkComplex
  doAssert promotedKind(nkComplex, nkInteger) == nkComplex
  doAssert promotedKind(nkInteger, nkComplex) == nkComplex

  doAssert not compiles(
    default(Integer[D]) / default(Integer[D])
  )
  doAssert not compiles(
    default(Integer[D]) div default(Real[D])
  )

suite "portable numeric interface":
  test "the selected adapter supplies each numeric family":
    let integerSingle = newInteger(1'i32)
    let integerDouble = newInteger(1'i64)
    let realSingle = newReal(1.0'f32)
    let realDouble = newReal(1.0)
    let complexSingle = newComplex(1.0'f32, 2.0'f32)
    let complexDouble = newComplex(1.0, 2.0)

    check integerSingle is Integer[S]
    check integerDouble is Integer[D]
    check realSingle is Real[S]
    check realDouble is Real[D]
    check complexSingle is Complex[S]
    check complexDouble is Complex[D]

  test "numeric kind and precision remain inspectable":
    check Integer[S].precision == S
    check Integer[D].numericKind == nkInteger
    check Real[S].precision == S
    check Real[D].numericKind == nkReal
    check Complex[D].precision == D
    check Complex[S].numericKind == nkComplex

  test "complex projections preserve precision":
    let single = newComplex(1.0'f32, 2.0'f32)
    let double = newComplex(1.0, 2.0)

    check single.re is Real[S]
    check single.im is Real[S]
    check double.re is Real[D]
    check double.im is Real[D]
    within Host:
      let field = newLattice([8, 8]).newField(Complex[D])
      let view = field.view(Read)
      let scalarSite = view[firstScalar(field.lattice)]
      check scalarSite.re is RealNumber[D]
      check scalarSite.im is RealNumber[D]

  test "same-Kind arithmetic is semantically closed":
    let integerSingle = newInteger(2'i32)
    let integerDouble = newInteger(2'i64)
    let realSingle = newReal(2.0'f32)
    let realDouble = newReal(2.0)
    let complexSingle = newComplex(2.0'f32, 1.0'f32)
    let complexDouble = newComplex(2.0, 1.0)

    check typeof(+integerSingle) is IntegerNumber[S]
    check typeof(-integerDouble) is IntegerNumber[D]
    check typeof(integerSingle + integerDouble) is IntegerNumber[D]
    check typeof(integerDouble - integerSingle) is IntegerNumber[D]
    check typeof(integerSingle * integerSingle) is IntegerNumber[S]
    check typeof(integerDouble div integerSingle) is IntegerNumber[D]
    check typeof(integerDouble mod integerSingle) is IntegerNumber[D]

    check typeof(+realSingle) is RealNumber[S]
    check typeof(-realDouble) is RealNumber[D]
    check typeof(realSingle + realDouble) is RealNumber[D]
    check typeof(realDouble - realSingle) is RealNumber[D]
    check typeof(realSingle * realSingle) is RealNumber[S]
    check typeof(realDouble / realSingle) is RealNumber[D]

    check typeof(+complexSingle) is ComplexNumber[S]
    check typeof(-complexDouble) is ComplexNumber[D]
    check typeof(complexSingle + complexDouble) is ComplexNumber[D]
    check typeof(complexDouble - complexSingle) is ComplexNumber[D]
    check typeof(complexSingle * complexSingle) is ComplexNumber[S]
    check typeof(complexDouble / complexSingle) is ComplexNumber[D]

  test "mixed arithmetic follows portable promotion":
    let integerSingle = newInteger(2'i32)
    let integerDouble = newInteger(2'i64)
    let realSingle = newReal(2.0'f32)
    let realDouble = newReal(2.0)
    let complexSingle = newComplex(2.0'f32, 1.0'f32)
    let complexDouble = newComplex(2.0, 1.0)

    check typeof(integerSingle + realDouble) is RealNumber[D]
    check typeof(realDouble + integerSingle) is RealNumber[D]
    check typeof(realSingle - integerDouble) is RealNumber[D]
    check typeof(integerSingle * complexDouble) is ComplexNumber[D]
    check typeof(complexDouble * integerSingle) is ComplexNumber[D]
    check typeof(complexSingle / integerDouble) is ComplexNumber[D]
    check typeof(realDouble + complexSingle) is ComplexNumber[D]
    check typeof(complexSingle + realDouble) is ComplexNumber[D]
    check typeof(complexDouble * realSingle) is ComplexNumber[D]

    let chained = (integerSingle + realDouble) * complexSingle
    check typeof(chained) is ComplexNumber[D]
    check typeof(chained) is ComplexArithmetic[D]
    check typeof(2.0'f32 * realSingle + 1.0'f32) is RealNumber[S]
    check typeof(2.0 * complexDouble + 1.0) is ComplexNumber[D]

  test "explicit and implicit scalar conversions select the adapter type":
    let explicitInteger = Integer[D](1'i64)
    let explicitReal = Real[D](1.0)
    let explicitComplex = Complex[D](1.0)
    let implicitInteger: Integer[D] = 1'i64
    let implicitReal: Real[D] = 1.0
    let implicitComplex: Complex[D] = 1.0

    check explicitInteger is Integer[D]
    check explicitReal is Real[D]
    check explicitComplex is Complex[D]
    check implicitInteger is Integer[D]
    check implicitReal is Real[D]
    check implicitComplex is Complex[D]
