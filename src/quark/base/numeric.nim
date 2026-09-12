#[
Numeric conformance

src: quark/base/numeric.nim
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

## Numeric classification, arithmetic, and promotion
## =================================================
##
## This module separates a number's portable mathematical properties from its
## concrete storage or expression representation. ``Precision`` records Half
## (``H``, 16-bit), Single (``S``, 32-bit), or Double (``D``, 64-bit) storage.
## ``NumericKind`` distinguishes Integer, Real, and Complex values. Declaring a
## Precision does not require every backend to implement it; unsupported
## representations must be rejected explicitly.
##
## ``IntegerNumber[P]`` and ``RealNumber[P]`` classify precision and kind.
## ``ComplexNumber[P]`` additionally requires an associated ``realType`` and
## real/imaginary projections of that Real type at the same precision.
## ``Numeric[P]`` accepts any of the three numeric families. These concepts can
## classify expression values as well as independently stored numbers.
##
## Arithmetic capability is separate from classification. Integer arithmetic
## requires unary signs, addition, subtraction, multiplication, ``div``, and
## ``mod``. Real and Complex arithmetic require unary signs and the four
## operations ``+``, ``-``, ``*``, and ``/``. Results at the concept's fixed
## precision retain their kind and precision; they need not retain the operand's concrete
## representation. This permits readable proxies and expression results without
## requiring eager materialization or a shared numeric base class.
##
## ``promotedPrecision`` chooses the wider operand precision.
## ``promotedKind`` chooses Complex over Real and Real over Integer. Together
## they describe mixed numeric result classification. Mixed operand pairs and
## chained results need their own conformance checks: matching a same-kind
## arithmetic concept alone does not establish every mixed operation.
##
## Constructors, conversions, assignment compatibility, and numerical observation
## operations such as comparison are checked separately from these concepts.
## The module does not choose narrowing behavior or a concrete numeric storage
## family. Nim remains responsible for syntax, precedence, and grouping; adapters
## connect the declared operations to their backend's numeric facilities.
##
## These contracts are also used recursively by tensor components and readable
## Field Site Proxies. A scalar numeric value and the numeric leaf of a Packed
## site can have different representations while retaining the same portable
## Precision and Numeric Kind.


type
  Precision* = enum
    ## The portable storage precision of a numeric value
    ##
    ## `H`, `S`, and `D` denote 16-, 32-, and 64-bit storage respectively.
    ## Precision is part of a numeric value's portable type and is independent
    ## of its backend representation. An adapter may explicitly reject a
    ## Precision that its backend cannot represent faithfully.
    H = 16 ## Half Precision
    S = 32 ## Single Precision
    D = 64 ## Double Precision

  NumericKind* = enum
    ## The portable mathematical category of a numeric value.
    nkInteger
    nkReal
    nkComplex

type
  IntegerNumber*[P: static Precision] = concept value, type T
    ## An adapter-owned integer value with portable Precision `P`
    ##
    ## The concept classifies concrete values and expressions. Construction,
    ## conversion, representation, and evaluation remain properties of the
    ## selected adapter.
    T.precision == P
    T.numericKind == nkInteger

  RealNumber*[P: static Precision] = concept value, type T
    ## An adapter-owned real value with portable Precision `P`
    ##
    ## The concept classifies concrete values and expressions. Construction,
    ## conversion, representation, and evaluation remain properties of the
    ## selected adapter.
    T.precision == P
    T.numericKind == nkReal

  ComplexNumber*[P: static Precision] = concept value, type T
    ## An adapter-owned complex value with portable Precision `P`
    ##
    ## Its real and imaginary projections are Real Numbers of the same
    ## Precision. The concept classifies concrete values and expressions;
    ## construction, conversion, representation, and evaluation remain
    ## properties of the selected adapter.
    T.precision == P
    T.numericKind == nkComplex
    T.realType is RealNumber[P]

    value.re is T.realType
    value.im is T.realType

  Numeric*[P: static Precision] = IntegerNumber[P] | RealNumber[P] | ComplexNumber[P]

type
  IntegerArithmetic*[P: static Precision] = concept value, other, type T
    ## Closed arithmetic over Integer Numbers of Precision `P`
    T.precision == P
    T.numericKind == nkInteger

    mixin `+`, `-`, `*`, `div`, `mod`

    +value is IntegerNumber[P]
    -value is IntegerNumber[P]

    value + other is IntegerNumber[P]
    value - other is IntegerNumber[P]
    value * other is IntegerNumber[P]
    value div other is IntegerNumber[P]
    value mod other is IntegerNumber[P]

  RealArithmetic*[P: static Precision] = concept value, other, type T
    ## Closed arithmetic over Real Numbers of Precision `P`
    T.precision == P
    T.numericKind == nkReal

    mixin `+`, `-`, `*`, `/`

    +value is RealNumber[P]
    -value is RealNumber[P]

    value + other is RealNumber[P]
    value - other is RealNumber[P]
    value * other is RealNumber[P]
    value / other is RealNumber[P]

  ComplexArithmetic*[P: static Precision] = concept value, other, type T
    ## Closed arithmetic over Complex Numbers of Precision `P`
    T.precision == P
    T.numericKind == nkComplex

    mixin `+`, `-`, `*`, `/`

    +value is ComplexNumber[P]
    -value is ComplexNumber[P]

    value + other is ComplexNumber[P]
    value - other is ComplexNumber[P]
    value * other is ComplexNumber[P]
    value / other is ComplexNumber[P]

func promotedPrecision*(a, b: Precision): Precision =
  ## Returns the wider of two Precisions
  return case a:
    of H: b
    of S: (if b == D: D else: S)
    of D: D

func promotedKind*(a, b: NumericKind): NumericKind =
  ## Returns the result kind for mixed-Kind arithmetic
  ##
  ## Complex dominates Real, and Real dominates Integer.
  return case a:
    of nkInteger: b
    of nkReal: (if b == nkComplex: nkComplex else: nkReal)
    of nkComplex: nkComplex

when isMainModule:
  import std/unittest

  # Signature witnesses test classification, not a substitute numeric backend.
  type
    Defect = enum
      valid,
      noPositive,
      noNegative,
      noAdd,
      noSubtract,
      noMultiply,
      noDivide,
      noModulo,
      wrongResultPrecision,
      wrongResultKind,
      noReal,
      noImaginary,
      wrongRealType,
      wrongRealProjection,
      wrongImaginaryProjection
    TestNumber[P: static Precision; K: static NumericKind; F: static Defect = valid] = object
    BareNumber[P: static Precision; K: static NumericKind] = object

  template precision[P, K, F](T: typedesc[TestNumber[P, K, F]]): Precision = P
  template numericKind[P, K, F](T: typedesc[TestNumber[P, K, F]]): NumericKind = K
  template precision[P, K](T: typedesc[BareNumber[P, K]]): Precision = P
  template numericKind[P, K](T: typedesc[BareNumber[P, K]]): NumericKind = K
  template realType[P, K, F](T: typedesc[TestNumber[P, K, F]]): typedesc =
    when F == wrongRealType: TestNumber[P, nkInteger]
    else: TestNumber[P, nkReal]
  func re[P, K, F](v: TestNumber[P, K, F]): auto =
    when F == noReal: {.error: "missing real projection".}
    elif F == wrongRealProjection: TestNumber[P, nkInteger]()
    else: TestNumber[P, nkReal]()
  func im[P, K, F](v: TestNumber[P, K, F]): auto =
    when F == noImaginary: {.error: "missing imaginary projection".}
    elif F == wrongImaginaryProjection: TestNumber[P, nkInteger]()
    else: TestNumber[P, nkReal]()

  template arithmeticResult(P, K, F: untyped): untyped =
    when F == wrongResultPrecision:
      when P == H: TestNumber[D, K]()
      else: TestNumber[H, K]()
    elif F == wrongResultKind:
      when K == nkInteger: TestNumber[P, nkReal]()
      else: TestNumber[P, nkInteger]()
    else: TestNumber[P, K]()

  template unary(symbol, missing: untyped) =
    func symbol[P, K, F](v: TestNumber[P, K, F]): auto =
      when F == missing: {.error: "missing unary operation".}
      else: arithmeticResult(P, K, F)
  template binary(symbol, missing: untyped) =
    func symbol[P, K, F](a, b: TestNumber[P, K, F]): auto =
      when F == missing: {.error: "missing binary operation".}
      else: arithmeticResult(P, K, F)

  unary(`+`, noPositive)
  unary(`-`, noNegative)
  binary(`+`, noAdd)
  binary(`-`, noSubtract)
  binary(`*`, noMultiply)
  binary(`/`, noDivide)
  binary(`div`, noDivide)
  binary(`mod`, noModulo)

  suite "numeric promotion":
    test "all precision pairs select the wider storage precision":
      const precisions = [H, S, D]
      const expected = [[H, S, D], [S, S, D], [D, D, D]]
      for i, a in precisions:
        for j, b in precisions:
          check promotedPrecision(a, b) == expected[i][j]

    test "all kind pairs follow integer real complex ordering":
      const expected = [[nkInteger, nkReal, nkComplex],
                        [nkReal, nkReal, nkComplex],
                        [nkComplex, nkComplex, nkComplex]]
      for a in NumericKind:
        for b in NumericKind:
          check promotedKind(a, b) == expected[ord(a)][ord(b)]

    test "precision promotion is associative and commutative":
      for a in [H, S, D]:
        check promotedPrecision(a, a) == a
        for b in [H, S, D]:
          check promotedPrecision(a, b) == promotedPrecision(b, a)
          for c in [H, S, D]:
            check promotedPrecision(promotedPrecision(a, b), c) ==
              promotedPrecision(a, promotedPrecision(b, c))

    test "kind promotion is associative and commutative":
      for a in NumericKind:
        check promotedKind(a, a) == a
        for b in NumericKind:
          check promotedKind(a, b) == promotedKind(b, a)
          for c in NumericKind:
            check promotedKind(promotedKind(a, b), c) ==
              promotedKind(a, promotedKind(b, c))

    test "promotion can be evaluated at compile time":
      const prec = promotedPrecision(H, S)
      const kind = promotedKind(nkReal, nkComplex)
      check prec == S
      check kind == nkComplex

  suite "numeric classification":
    test "Integer at H has exactly its declared kind and precision":
      check TestNumber[H, nkInteger] is IntegerNumber[H]
      check TestNumber[H, nkInteger] is Numeric[H]
      check TestNumber[H, nkInteger] is IntegerArithmetic[H]
      check TestNumber[H, nkInteger] isnot Numeric[S]
      check TestNumber[H, nkInteger] isnot Numeric[D]
      check TestNumber[H, nkInteger] isnot RealNumber[H]
      check TestNumber[H, nkInteger] isnot ComplexNumber[H]
    test "Real at H has exactly its declared kind and precision":
      check TestNumber[H, nkReal] is RealNumber[H]
      check TestNumber[H, nkReal] is Numeric[H]
      check TestNumber[H, nkReal] is RealArithmetic[H]
      check TestNumber[H, nkReal] isnot Numeric[S]
      check TestNumber[H, nkReal] isnot Numeric[D]
      check TestNumber[H, nkReal] isnot IntegerNumber[H]
      check TestNumber[H, nkReal] isnot ComplexNumber[H]
    test "Complex at H has exactly its declared kind and precision":
      check TestNumber[H, nkComplex] is ComplexNumber[H]
      check TestNumber[H, nkComplex] is Numeric[H]
      check TestNumber[H, nkComplex] is ComplexArithmetic[H]
      check TestNumber[H, nkComplex] isnot Numeric[S]
      check TestNumber[H, nkComplex] isnot Numeric[D]
      check TestNumber[H, nkComplex] isnot IntegerNumber[H]
      check TestNumber[H, nkComplex] isnot RealNumber[H]
    test "Integer at S has exactly its declared kind and precision":
      check TestNumber[S, nkInteger] is IntegerNumber[S]
      check TestNumber[S, nkInteger] is Numeric[S]
      check TestNumber[S, nkInteger] is IntegerArithmetic[S]
      check TestNumber[S, nkInteger] isnot Numeric[H]
      check TestNumber[S, nkInteger] isnot Numeric[D]
      check TestNumber[S, nkInteger] isnot RealNumber[S]
      check TestNumber[S, nkInteger] isnot ComplexNumber[S]
    test "Real at S has exactly its declared kind and precision":
      check TestNumber[S, nkReal] is RealNumber[S]
      check TestNumber[S, nkReal] is Numeric[S]
      check TestNumber[S, nkReal] is RealArithmetic[S]
      check TestNumber[S, nkReal] isnot Numeric[H]
      check TestNumber[S, nkReal] isnot Numeric[D]
      check TestNumber[S, nkReal] isnot IntegerNumber[S]
      check TestNumber[S, nkReal] isnot ComplexNumber[S]
    test "Complex at S has exactly its declared kind and precision":
      check TestNumber[S, nkComplex] is ComplexNumber[S]
      check TestNumber[S, nkComplex] is Numeric[S]
      check TestNumber[S, nkComplex] is ComplexArithmetic[S]
      check TestNumber[S, nkComplex] isnot Numeric[H]
      check TestNumber[S, nkComplex] isnot Numeric[D]
      check TestNumber[S, nkComplex] isnot IntegerNumber[S]
      check TestNumber[S, nkComplex] isnot RealNumber[S]
    test "Integer at D has exactly its declared kind and precision":
      check TestNumber[D, nkInteger] is IntegerNumber[D]
      check TestNumber[D, nkInteger] is Numeric[D]
      check TestNumber[D, nkInteger] is IntegerArithmetic[D]
      check TestNumber[D, nkInteger] isnot Numeric[H]
      check TestNumber[D, nkInteger] isnot Numeric[S]
      check TestNumber[D, nkInteger] isnot RealNumber[D]
      check TestNumber[D, nkInteger] isnot ComplexNumber[D]
    test "Real at D has exactly its declared kind and precision":
      check TestNumber[D, nkReal] is RealNumber[D]
      check TestNumber[D, nkReal] is Numeric[D]
      check TestNumber[D, nkReal] is RealArithmetic[D]
      check TestNumber[D, nkReal] isnot Numeric[H]
      check TestNumber[D, nkReal] isnot Numeric[S]
      check TestNumber[D, nkReal] isnot IntegerNumber[D]
      check TestNumber[D, nkReal] isnot ComplexNumber[D]
    test "Complex at D has exactly its declared kind and precision":
      check TestNumber[D, nkComplex] is ComplexNumber[D]
      check TestNumber[D, nkComplex] is Numeric[D]
      check TestNumber[D, nkComplex] is ComplexArithmetic[D]
      check TestNumber[D, nkComplex] isnot Numeric[H]
      check TestNumber[D, nkComplex] isnot Numeric[S]
      check TestNumber[D, nkComplex] isnot IntegerNumber[D]
      check TestNumber[D, nkComplex] isnot RealNumber[D]
    test "metadata alone classifies integers and reals but not arithmetic":
      check BareNumber[D, nkInteger] is IntegerNumber[D]
      check BareNumber[D, nkReal] is RealNumber[D]
      check BareNumber[D, nkInteger] isnot IntegerArithmetic[D]
      check BareNumber[D, nkReal] isnot RealArithmetic[D]

    test "complex metadata requires projections":
      check BareNumber[D, nkComplex] isnot ComplexNumber[D]

    test "ordinary built-in numbers lack portable metadata":
      check int isnot Numeric[D]
      check float64 isnot Numeric[D]
      check string isnot Numeric[D]
    test "complex classification rejects noReal":
      check TestNumber[D, nkComplex, noReal] isnot ComplexNumber[D]
    test "complex classification rejects noImaginary":
      check TestNumber[D, nkComplex, noImaginary] isnot ComplexNumber[D]
    test "complex classification rejects wrongRealType":
      check TestNumber[D, nkComplex, wrongRealType] isnot ComplexNumber[D]
    test "complex classification rejects wrongRealProjection":
      check TestNumber[D, nkComplex, wrongRealProjection] isnot ComplexNumber[D]
    test "complex classification rejects wrongImaginaryProjection":
      check TestNumber[D, nkComplex, wrongImaginaryProjection] isnot ComplexNumber[D]

  suite "arithmetic capability rejection":
    test "each arithmetic family rejects noPositive":
      check TestNumber[D, nkInteger, noPositive] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, noPositive] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, noPositive] isnot ComplexArithmetic[D]
    test "each arithmetic family rejects noNegative":
      check TestNumber[D, nkInteger, noNegative] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, noNegative] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, noNegative] isnot ComplexArithmetic[D]
    test "each arithmetic family rejects noAdd":
      check TestNumber[D, nkInteger, noAdd] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, noAdd] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, noAdd] isnot ComplexArithmetic[D]
    test "each arithmetic family rejects noSubtract":
      check TestNumber[D, nkInteger, noSubtract] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, noSubtract] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, noSubtract] isnot ComplexArithmetic[D]
    test "each arithmetic family rejects noMultiply":
      check TestNumber[D, nkInteger, noMultiply] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, noMultiply] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, noMultiply] isnot ComplexArithmetic[D]
    test "each arithmetic family rejects noDivide":
      check TestNumber[D, nkInteger, noDivide] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, noDivide] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, noDivide] isnot ComplexArithmetic[D]
    test "each arithmetic family rejects wrongResultPrecision":
      check TestNumber[D, nkInteger, wrongResultPrecision] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, wrongResultPrecision] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, wrongResultPrecision] isnot ComplexArithmetic[D]
    test "each arithmetic family rejects wrongResultKind":
      check TestNumber[D, nkInteger, wrongResultKind] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, wrongResultKind] isnot RealArithmetic[D]
      check TestNumber[D, nkComplex, wrongResultKind] isnot ComplexArithmetic[D]
    test "integer arithmetic also requires modulo":
      check TestNumber[D, nkInteger, noModulo] isnot IntegerArithmetic[D]
      check TestNumber[D, nkReal, noModulo] is RealArithmetic[D]
      check TestNumber[D, nkComplex, noModulo] is ComplexArithmetic[D]

    test "arithmetic results may use a different concrete representation":
      type Expression = TestNumber[D, nkReal, noModulo]
      check typeof(default(Expression) + default(Expression)) isnot Expression
      check Expression is RealArithmetic[D]
