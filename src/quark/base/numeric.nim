#[
Numeric types

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
