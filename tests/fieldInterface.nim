import std/unittest
import quark

include support/siteIndices

# Constructor conformance is separate from FieldObject classification. Exercise
# the same concrete family names and constructor callers use via import quark.
template assertConstruction(source: untyped; T, Expected: typedesc) =
  static:
    doAssert typeof(source.newField(T)) is Expected
    doAssert Expected is typeof(source.newField(T))
    doAssert typeof(source.newField(T)) is FieldObject[T]
    doAssert typeof(source.newField(T).lattice) is typeof(source)
    doAssert source.newField(T).lattice.domain == source.domain

template checkConstruction(source: untyped; T: typedesc) =
  block:
    assertConstruction(source, T, Field[T, typeof(source)])
    let field = source.newField(T)
    check not field.isNil
    check conformable(field.lattice, source)
    check conformable(source, field.lattice)

suite "portable Field classification and construction":
  test "numeric site types retain their classification and Lattice":
    let source = newLattice([8, 8], packedPartition = [2, 1])
    checkConstruction(source, Integer[S])
    checkConstruction(source, Real[D])
    checkConstruction(source, Complex[D])
    static:
      doAssert Field[Complex[D]] is FieldObject[Complex[D]]
      doAssert not (Field[Complex[D]] is FieldObject[Real[D]])
      doAssert not (Field[Complex[D]] is FieldObject[Complex[S]])
      doAssert not (Complex[D] is FieldObject[Complex[D]])
      doAssert not compiles(source.newField(newComplex(1.0, 0.0)))
      doAssert not compiles(source.newField())
      doAssert not compiles(newField(42, Complex[D]))
      doAssert not compiles(assertConstruction(source, Complex[D], Field[Real[D]]))

  test "copies alias a handle, separate constructions create separate Fields":
    let source = newLattice([8, 8])
    let field: Field[Complex[D]] = source.newField(Complex[D])
    let alias = field
    let other = source.newField(Complex[D])
    check system.`==`(field, alias)
    check not system.`==`(field, other)
    check conformable(field.lattice, other.lattice)
    var fields: seq[Field[Complex[D]]]
    fields.add field
    fields.add source.newField(Complex[D])
    check system.`==`(fields[0], field)
    static:
      doAssert not compiles(field.lattice = newLattice([8, 8]))
      doAssert not compiles(field.latticeData = source)

  test "construction preserves the supplied association, not equal extents":
    let source = newLattice([8, 8])
    let other = newLattice([8, 8])
    let field = source.newField(Real[D])
    check not conformable(field.lattice, other)
    let full = source.newSublattice(Full)
    checkConstruction(full, Real[D])

  test "derived Lattice constructor signatures preserve the selected type":
    # Parity construction remains unsupported at runtime in both adapters.
    # Check Field construction on those types without executing derivation.
    type
      Even = typeof(newLattice([8, 8]).newSublattice(EvenParity))
      Odd = typeof(newLattice([8, 8]).newSublattice(OddParity))
    assertConstruction(newLattice([8, 8]).newSublattice(EvenParity), Complex[D], Field[Complex[D], Even])
    assertConstruction(newLattice([8, 8]).newSublattice(OddParity), Complex[D], Field[Complex[D], Odd])
    static:
      doAssert not (Field[Complex[D], Even] is Field[Complex[D], Odd])
      doAssert not (Field[Complex[D], Even] is Field[Complex[D]])

  test "concrete views retain modes, association, and both index kinds":
    let source = newLattice([8, 8])
    let field = source.newField(Complex[D])
    template checkView(access: static ViewMode) =
      within Host:
        var view = field.view(access)
        var annotated: FieldView[Complex[D], access] = view
        static:
          doAssert typeof(view) is FieldView[Complex[D], access]
          doAssert FieldView[Complex[D], access] is typeof(view)
          doAssert typeof(view) is FieldViewObject[Complex[D]]
          doAssert annotated.mode == access
          doAssert view.mode == access
          doAssert typeof(view[firstScalar(source)]) is FieldSiteProxy[Complex[D], ScalarIndex]
          doAssert typeof(view[firstPacked(source)]) is FieldSiteProxy[Complex[D], PackedIndex]
          doAssert not (typeof(view[firstScalar(source)]) is FieldSiteProxy[Complex[D], PackedIndex])
          doAssert not (typeof(view[firstScalar(source)]) is FieldSiteProxy[Real[D], ScalarIndex])
          doAssert view[firstScalar(source)].mode == access
          doAssert view[firstPacked(source)].mode == access
          doAssert not compiles(view[ScalarIndex])
          doAssert not compiles(view[0])
        check conformable(view.lattice, field.lattice)
        check conformable(annotated.lattice, field.lattice)
    checkView(Read)
    checkView(ReadWrite)
    checkView(WriteDiscard)

  test "view types distinguish access modes and Lattice kinds":
    let source = newLattice([8, 8])
    let field = source.newField(Complex[D])
    type Even = typeof(source.newSublattice(EvenParity))
    within Host:
      static:
        doAssert not (FieldView[Complex[D], Read] is FieldView[Complex[D], ReadWrite])
        doAssert not compiles(block:
          var view: FieldView[Complex[D], Read] = field.view(WriteDiscard))
        doAssert not compiles(block:
          var view: FieldView[Real[D], Read] = field.view(Read))
        doAssert not compiles(block:
          var access = Read
          discard field.view(access))
        type Derived = typeof(block:
          within Host: default(Field[Complex[D], Even]).view(Read))
        doAssert Derived is FieldView[Complex[D], Read, Even]
        doAssert FieldView[Complex[D], Read, Even] is Derived
        doAssert Derived is FieldViewObject[Complex[D]]
        doAssert not (Derived is FieldView[Complex[D], Read])
