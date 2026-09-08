#[
Field

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

import lattice
import iteration
import numeric
import tensor

type ViewMode* = enum
  Read = 0,
  WriteDiscard = 1,
  ReadWrite = 2

type
  Field*[T] = object
  FieldView*[T] = object
  FieldSite*[T,I] = object

proc newScalarField*[T](lattice: Lattice; t: typedesc[T]): Field[T] =
  discard lattice
  return Field[T]()

proc view*[T](field: Field[T]; mode: ViewMode): FieldView[T] =
  return FieldView[T]()

proc `[]`*[T](field: FieldView[T]; site: ScalarSite): FieldSite[T, ScalarSite] =
  discard field
  discard site
  return FieldSite[T, ScalarSite]()

proc `[]`*[T](field: FieldView[T]; site: PackedSite): FieldSite[T, PackedSite] =
  discard field
  discard site
  return FieldSite[T, PackedSite]()

proc `:=`*[A,B](a: Field[A]; b: Field[B]) =
  discard

proc `:=`*[T](a: Field[T]; b: T) =
  discard

proc `:=`*[A,B,I](a: FieldSite[A,I]; b: FieldSite[B,I]) =
  discard a
  discard b

proc `:=`*[T,I](a: FieldSite[T,I]; b: T) =
  discard a
  discard b

proc `*`*[A,T,I](a: A; b: FieldSite[T,I]): FieldSite[T,I] =
  discard a
  return b

proc `+`*[T,I,A](a: FieldSite[T,I]; b: A): FieldSite[T,I] =
  discard b
  return a

proc `+=`*[A,B,I](a: FieldSite[A,I]; b: FieldSite[B,I]) =
  discard a
  discard b

proc re*[P: static Precision; T: ComplexNumber[P]](
  site: FieldSite[T, ScalarSite]
): FieldSite[T.realType, ScalarSite] =
  discard site
  return FieldSite[T.realType, ScalarSite]()

proc im*[P: static Precision; T: ComplexNumber[P]](
  site: FieldSite[T, ScalarSite]
): FieldSite[T.realType, ScalarSite] =
  discard site
  return FieldSite[T.realType, ScalarSite]()

proc `+`*[A,B](a: Field[A]; b: Field[B]): Field[typeof(default(A) + default(B))] =
  return Field[typeof(default(A) + default(B))]()

proc `+`*[A,B](a: Field[A]; b: B): Field[typeof(default(A) + default(B))] =
  return Field[typeof(default(A) + default(B))]()

proc `+`*[A,B](a: A; b: Field[B]): Field[typeof(default(A) + default(B))] =
  return b + a

proc `+`*[A,B](a: FieldView[A]; b: FieldView[B]): FieldView[typeof(default(A) + default(B))] =
  return FieldView[typeof(default(A) + default(B))]()

proc `+`*[A,B](a: FieldView[A]; b: B): FieldView[typeof(default(A) + default(B))] =
  return FieldView[typeof(default(A) + default(B))]()

proc `+`*[A,B](a: B; b: FieldView[B]): FieldView[typeof(default(A) + default(B))] =
  return b + a

proc `-`*[A,B](a: Field[A]; b: Field[B]): Field[typeof(default(A) - default(B))] =
  return Field[typeof(default(A) - default(B))]()

proc `-`*[A,B](a: Field[A]; b: B): Field[typeof(default(A) - default(B))] =
  return Field[typeof(default(A) - default(B))]()

proc `-`*[A,B](a: A; b: Field[B]): Field[typeof(default(A) - default(B))] =
  return Field[typeof(default(A) - default(B))]()

proc `-`*[A,B](a: FieldView[A]; b: FieldView[B]): FieldView[typeof(default(A) - default(B))] =
  return FieldView[typeof(default(A) - default(B))]()

proc `-`*[A,B](a: FieldView[A]; b: B): FieldView[typeof(default(A) - default(B))] =
  return FieldView[typeof(default(A) - default(B))]()

proc `-`*[A,B](a: B; b: FieldView[B]): FieldView[typeof(default(A) - default(B))] =
  return b - a

proc `*`*[A,B](a: Field[A]; b: Field[B]): Field[typeof(default(A) * default(B))] =
  return Field[typeof(default(A) * default(B))]()

proc `*`*[A,B](a: Field[A]; b: B): Field[typeof(default(A) * default(B))] =
  return Field[typeof(default(A) * default(B))]()

proc `*`*[A,B](a: A; b: Field[B]): Field[typeof(default(A) * default(B))] =
  return Field[typeof(default(A) * default(B))]()

proc `*`*[A,B](a: FieldView[A]; b: FieldView[B]): FieldView[typeof(default(A) * default(B))] =
  return FieldView[typeof(default(A) * default(B))]()

proc `*`*[A,B](a: FieldView[A]; b: B): FieldView[typeof(default(A) * default(B))] =
  return FieldView[typeof(default(A) * default(B))]()

proc `*`*[A,B](a: B; b: FieldView[B]): FieldView[typeof(default(A) * default(B))] =
  return b * a

when isMainModule:
  import std/unittest
  import quark/backend/backend

  suite "field assignment conversions":
    test "scalar values convert to the destination element type":
      var field: Field[Complex[D]]
      var site: FieldSite[Complex[D], ScalarSite]

      field := 2.0
      site := 2.0

    test "scalar and packed site accesses remain distinct":
      let lattice = newLattice([8, 8, 8, 16])
      var field: Field[Complex[D]]
      let view = field.view(Read)

      for site in lattice.sites(Scalar):
        check view[site] is FieldSite[Complex[D], ScalarSite]
      for site in lattice.sites(Packed):
        check view[site] is FieldSite[Complex[D], PackedSite]

    test "oracle site expressions type check":
      var scalarSite: FieldSite[Complex[D], ScalarSite]
      var packedSiteA, packedSiteB: FieldSite[Complex[D], PackedSite]

      check scalarSite.re is FieldSite[Real[D], ScalarSite]
      check scalarSite.im is FieldSite[Real[D], ScalarSite]
      packedSiteA := 2.0 * packedSiteB + 1.0
      packedSiteA += packedSiteB
