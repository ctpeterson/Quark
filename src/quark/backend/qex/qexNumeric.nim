#[
Quantum EXpressions Numeric implementation

This is sketch work for Milestone 1 that should not be taken as a final
implementation. Once the implementation is finalized (Milestone 2), this notice must
be permanently removed.

src: quark/backend/qex/qexNumeric.nim
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

import quark/base/[numeric]

type
  Integer*[P: static Precision] = object
  Real*[P: static Precision] = object
  Complex*[P: static Precision] = object

template precision*[P](T: typedesc[Integer[P]]): Precision =
  P

template precision*[P](T: typedesc[Real[P]]): Precision =
  P

template precision*[P](T: typedesc[Complex[P]]): Precision =
  P

template numericKind*[P](T: typedesc[Integer[P]]): NumericKind =
  nkInteger

template numericKind*[P](T: typedesc[Real[P]]): NumericKind =
  nkReal

template numericKind*[P](T: typedesc[Complex[P]]): NumericKind =
  nkComplex

template realType*[P](T: typedesc[Complex[P]]): typedesc =
  Real[P]

template defineUnaryArithmetic(Number: untyped) =
  func `+`*[P: static Precision](value: Number[P]): Number[P] =
    value

  func `-`*[P: static Precision](value: Number[P]): Number[P] =
    value

template defineRingArithmetic(Lhs, Rhs, Result: untyped) =
  func `+`*[P, Q: static Precision](
    lhs: Lhs[P]; rhs: Rhs[Q]
  ): Result[promotedPrecision(P, Q)] =
    Result[promotedPrecision(P, Q)]()

  func `-`*[P, Q: static Precision](
    lhs: Lhs[P]; rhs: Rhs[Q]
  ): Result[promotedPrecision(P, Q)] =
    Result[promotedPrecision(P, Q)]()

  func `*`*[P, Q: static Precision](
    lhs: Lhs[P]; rhs: Rhs[Q]
  ): Result[promotedPrecision(P, Q)] =
    Result[promotedPrecision(P, Q)]()

template defineDivision(Lhs, Rhs, Result: untyped) =
  func `/`*[P, Q: static Precision](
    lhs: Lhs[P]; rhs: Rhs[Q]
  ): Result[promotedPrecision(P, Q)] =
    Result[promotedPrecision(P, Q)]()

template defineScalarRingArithmetic(
  Scalar, ScalarPrecision, Rhs, Result: untyped
) =
  func `+`*[P: static Precision](
    lhs: Scalar; rhs: Rhs[P]
  ): Result[promotedPrecision(ScalarPrecision, P)] =
    Result[promotedPrecision(ScalarPrecision, P)]()

  func `+`*[P: static Precision](
    lhs: Rhs[P]; rhs: Scalar
  ): Result[promotedPrecision(P, ScalarPrecision)] =
    Result[promotedPrecision(P, ScalarPrecision)]()

  func `-`*[P: static Precision](
    lhs: Scalar; rhs: Rhs[P]
  ): Result[promotedPrecision(ScalarPrecision, P)] =
    Result[promotedPrecision(ScalarPrecision, P)]()

  func `-`*[P: static Precision](
    lhs: Rhs[P]; rhs: Scalar
  ): Result[promotedPrecision(P, ScalarPrecision)] =
    Result[promotedPrecision(P, ScalarPrecision)]()

  func `*`*[P: static Precision](
    lhs: Scalar; rhs: Rhs[P]
  ): Result[promotedPrecision(ScalarPrecision, P)] =
    Result[promotedPrecision(ScalarPrecision, P)]()

  func `*`*[P: static Precision](
    lhs: Rhs[P]; rhs: Scalar
  ): Result[promotedPrecision(P, ScalarPrecision)] =
    Result[promotedPrecision(P, ScalarPrecision)]()

template defineScalarDivision(
  Scalar, ScalarPrecision, Rhs, Result: untyped
) =
  func `/`*[P: static Precision](
    lhs: Scalar; rhs: Rhs[P]
  ): Result[promotedPrecision(ScalarPrecision, P)] =
    Result[promotedPrecision(ScalarPrecision, P)]()

  func `/`*[P: static Precision](
    lhs: Rhs[P]; rhs: Scalar
  ): Result[promotedPrecision(P, ScalarPrecision)] =
    Result[promotedPrecision(P, ScalarPrecision)]()


defineUnaryArithmetic(Integer)
defineUnaryArithmetic(Real)
defineUnaryArithmetic(Complex)

defineRingArithmetic(Integer, Integer, Integer)
defineRingArithmetic(Integer, Real, Real)
defineRingArithmetic(Real, Integer, Real)
defineRingArithmetic(Integer, Complex, Complex)
defineRingArithmetic(Complex, Integer, Complex)
defineRingArithmetic(Real, Real, Real)
defineRingArithmetic(Real, Complex, Complex)
defineRingArithmetic(Complex, Real, Complex)
defineRingArithmetic(Complex, Complex, Complex)

func `div`*[P, Q: static Precision](
  lhs: Integer[P]; rhs: Integer[Q]
): Integer[promotedPrecision(P, Q)] =
  Integer[promotedPrecision(P, Q)]()

func `mod`*[P, Q: static Precision](
  lhs: Integer[P]; rhs: Integer[Q]
): Integer[promotedPrecision(P, Q)] =
  Integer[promotedPrecision(P, Q)]()

defineDivision(Integer, Real, Real)
defineDivision(Real, Integer, Real)
defineDivision(Integer, Complex, Complex)
defineDivision(Complex, Integer, Complex)
defineDivision(Real, Real, Real)
defineDivision(Real, Complex, Complex)
defineDivision(Complex, Real, Complex)
defineDivision(Complex, Complex, Complex)

defineScalarRingArithmetic(float32, S, Real, Real)
defineScalarRingArithmetic(float32, S, Complex, Complex)
defineScalarRingArithmetic(float64, D, Real, Real)
defineScalarRingArithmetic(float64, D, Complex, Complex)

defineScalarDivision(float32, S, Real, Real)
defineScalarDivision(float32, S, Complex, Complex)
defineScalarDivision(float64, D, Real, Real)
defineScalarDivision(float64, D, Complex, Complex)


converter newInteger*(value: int32): Integer[S] =
  Integer[S]()

converter newInteger*(value: int64): Integer[D] =
  Integer[D]()

converter newReal*(value: float32): Real[S] =
  Real[S]()

converter newReal*(value: float64): Real[D] =
  Real[D]()

converter newReal*(value: int32): Real[S] =
  Real[S]()

converter newReal*(value: int64): Real[D] =
  Real[D]()

converter newComplex*[P: static Precision](re: Real[P]): Complex[P] =
  Complex[P]()

converter newComplex*(re: float32): Complex[S] =
  newComplex(newReal(re))

converter newComplex*(re: float64): Complex[D] =
  newComplex(newReal(re))

converter newComplex*(re: int32): Complex[S] =
  newComplex(newReal(re))

converter newComplex*(re: int64): Complex[D] =
  newComplex(newReal(re))

proc newComplex*[P: static Precision](re, im: Real[P]): Complex[P] =
  Complex[P]()

proc newComplex*(re, im: float32): Complex[S] =
  newComplex(newReal(re), newReal(im))

proc newComplex*(re, im: float64): Complex[D] =
  newComplex(newReal(re), newReal(im))

proc newComplex*(re, im: int32): Complex[S] =
  newComplex(newReal(re), newReal(im))

proc newComplex*(re, im: int64): Complex[D] =
  newComplex(newReal(re), newReal(im))

func re*[P: static Precision](value: Complex[P]): Real[P] =
  Real[P]()

func im*[P: static Precision](value: Complex[P]): Real[P] =
  Real[P]()

static: # conformance - practice should be carried over to final implementation
  doAssert Integer[S] is IntegerNumber[S]
  doAssert Integer[D] is IntegerNumber[D]
  doAssert Real[S] is RealNumber[S]
  doAssert Real[D] is RealNumber[D]
  doAssert Complex[S] is ComplexNumber[S]
  doAssert Complex[D] is ComplexNumber[D]
  doAssert Integer[S] is IntegerArithmetic[S]
  doAssert Integer[D] is IntegerArithmetic[D]
  doAssert Real[S] is RealArithmetic[S]
  doAssert Real[D] is RealArithmetic[D]
  doAssert Complex[S] is ComplexArithmetic[S]
  doAssert Complex[D] is ComplexArithmetic[D]
  doAssert not (Integer[S] is RealNumber[S])
  doAssert not (Real[S] is RealNumber[D])
  doAssert not (Complex[S] is ComplexNumber[D])
  doAssert typeof(newComplex(2.0, 4.0)) is Complex[D]

when isMainModule: # always nice to have unit tests when main module
  import std/[unittest]