#[
QEX Field scaffold

src: quark/backend/qex/qexField.nim
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

# Milestone 1 shared-handle and view conformance scaffold.
import quark/base/[field, lattice, iteration, execution]
import ../common/commonField
import qexLattice
import qexNumeric
import quark/base/numeric

export field
export commonField except ScaffoldSite, assignFieldScaffold, newScaffoldSite

type
  Field*[T; L = typeof(newLattice([1, 1, 1, 1]))] = ref object
    latticeData: L
  FieldView*[T; M: static ViewMode; L = typeof(newLattice([1, 1, 1, 1]))] = object
    fieldData: Field[T, L]
    ownerData: ViewOwner
    spaceData: ExecutionSpace

template siteType*[T, L](F: typedesc[Field[T, L]]): typedesc = T

func lattice*[T, L](field: Field[T, L]): L =
  field.latticeData

proc newField*[T; L: Lattice](lattice: L; siteType: typedesc[T]): Field[T, L] =
  Field[T, L](latticeData: lattice)

template siteType*[T, M, L](V: typedesc[FieldView[T, M, L]]): typedesc = T
template mode*[T, M, L](view: FieldView[T, M, L]): ViewMode = M

func lattice*[T, M, L](view: FieldView[T, M, L]): L =
  view.fieldData.lattice

proc openFieldView[T, L](field: Field[T, L]; mode: static ViewMode;
                         space: static ExecutionSpace; scope: ExecutionScope): FieldView[T, mode, L] =
  FieldView[T, mode, L](fieldData: field, ownerData: openView(scope), spaceData: space)

template view*[T, L](field: Field[T, L]; mode: static ViewMode): untyped =
  openFieldView(field, mode, executionSpace(), executionScope())

proc accessSite[T, M, L; S: Site](view: FieldView[T, M, L]; site: S;
                                space: static ExecutionSpace): ScaffoldSite[T, S, M] =
  when view.lattice.domain != site.lattice.domain:
    {.error: "Site Index and Field have incompatible Lattice kinds".}
  requireOpen(view.ownerData.lease)
  if view.spaceData != space:
    raise newException(ValueError, "Field View belongs to a different Execution Context placement")
  if not conformable(view.lattice, site.lattice):
    raise newException(ValueError, "Site Index and Field have incompatible Lattice instances")
  newScaffoldSite[T, S, M](view.ownerData.lease)

template `[]`*[T, M, L; S: Site](view: FieldView[T, M, L]; site: S): untyped =
  accessSite(view, site, executionSpace())

template `:=`*[T, L, R](field: Field[T, L]; value: R) =
  assignFieldScaffold(field, value, fieldExecutionSpace())

static:
  # Classification does not require a constructor. Check that this adapter's
  # constructor returns its advertised concrete family for each numeric kind.
  template assertView(T: typedesc; access: static ViewMode) =
    type Viewed = typeof(block:
      within Host: default(Field[T]).view(access))
    doAssert Viewed is FieldView[T, access]
    doAssert FieldView[T, access] is Viewed
    doAssert Viewed is FieldViewObject[T]

  template assertConstructor(T: typedesc) =
    type Constructed = typeof(newLattice([8, 8]).newField(T))
    doAssert Constructed is Field[T]
    doAssert Field[T] is Constructed
    doAssert Constructed is FieldObject[T]
    assertView(T, Read)
    assertView(T, WriteDiscard)
    assertView(T, ReadWrite)
    doAssert newLattice([8, 8]).newField(T).lattice.domain == Full
  assertConstructor(Integer[S])
  assertConstructor(Real[D])
  assertConstructor(Complex[D])
