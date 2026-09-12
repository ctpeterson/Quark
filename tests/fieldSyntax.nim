import std/unittest
import quark

include support/siteIndices

# These are syntax and rejection checks, not numerical Field acceptance.
suite "Field adapter syntax scaffold":
  test "numeric site algebra preserves kind, precision, and granularity":
    template checkAlgebra(SiteIndex: typedesc; access: static ViewMode) =
      within Host:
        let lattice = newLattice([8, 8])
        let integers = lattice.newField(Integer[S]).view(access)
        let reals = lattice.newField(Real[S]).view(access)
        let complexes = lattice.newField(Complex[D]).view(access)
        let site = when SiteIndex is ScalarSite: firstScalar(lattice) else: firstPacked(lattice)
        static:
          doAssert typeof(integers[site]) is IntegerArithmetic[S]
          doAssert typeof(reals[site]) is RealArithmetic[S]
          doAssert typeof(complexes[site]) is ComplexArithmetic[D]
          doAssert typeof(integers[site] div integers[site]) is IntegerNumber[S]
          doAssert typeof(integers[site] mod integers[site]) is IntegerNumber[S]
          doAssert not compiles(integers[site] / integers[site])
          doAssert typeof((reals[site] + reals[site]) * reals[site]) is RealArithmetic[S]
          doAssert typeof(reals[site] + complexes[site]) is ComplexArithmetic[D]
          doAssert typeof(complexes[site] + reals[site]) is ComplexArithmetic[D]
          doAssert typeof(newComplex(1.0, 2.0) * complexes[site]) is ComplexArithmetic[D]
          doAssert typeof(complexes[site] * newComplex(1.0, 2.0)) is ComplexArithmetic[D]
          doAssert typeof(complexes[site] / complexes[site]).indexType is SiteIndex
          doAssert typeof((complexes[site] + complexes[site]).im) is RealArithmetic[D]
          doAssert typeof(complexes[site].im).indexType is SiteIndex
          doAssert not (typeof(reals[site] + reals[site]) is FieldSiteProxy[Real[S], SiteIndex])
          doAssert not compiles((reals[site] + reals[site]) := 1.0)
          doAssert not compiles(reals[site] + complexes[firstPacked(lattice)] + complexes[firstScalar(lattice)])
    checkAlgebra(ScalarIndex, Read)
    checkAlgebra(PackedIndex, Read)
    checkAlgebra(ScalarIndex, ReadWrite)
    checkAlgebra(PackedIndex, ReadWrite)

  test "initialization requires a compatible site value and explicit context":
    let field = newLattice([8, 8]).newField(Complex[D])
    static:
      doAssert compiles(block:
        within Host: field := 2.0)
      doAssert compiles(block:
        within Accelerator: field := newComplex(2.0, 4.0))
      doAssert not compiles(field := 2.0)
      doAssert not compiles(block:
        within Host: field := "invalid")
      doAssert not compiles(field + field)
    expect ValueError:
      within Host: field := 2.0
    expect ValueError:
      within Accelerator: field := newComplex(2.0, 4.0)

  test "site syntax checks access permissions and index kinds":
    let field = newLattice([8, 8]).newField(Complex[D])
    within Host:
      let read = field.view(Read)
      let write = field.view(WriteDiscard)
      let update = field.view(ReadWrite)
      let scalar = firstScalar(field.lattice)
      let packed = firstPacked(field.lattice)
      static:
        doAssert compiles(write[packed] := 2.0 * read[packed] + 1.0)
        doAssert compiles(write[packed] := read[packed])
        doAssert compiles(update[packed] += read[packed])
        doAssert not compiles(read[packed] := 2.0)
        doAssert not compiles(read[packed] := update[packed])
        doAssert not compiles(write[packed] += read[packed])
        doAssert not compiles(update[packed] += write[packed])
        doAssert not compiles(update[packed] := write[packed])
        doAssert not compiles(2.0 * write[packed])
        doAssert not compiles(write[packed] == write[packed])
        doAssert not compiles(write[scalar].re)
        doAssert not compiles(write[scalar].im)
        doAssert typeof(read[packed].re) is RealNumber[D]
        doAssert typeof(read[packed].re).indexType is PackedIndex
        doAssert not compiles(write[scalar] := read[packed])
        doAssert not compiles(write[packed] := "invalid")
      expect ValueError:
        write[packed] := 2.0
      expect ValueError:
        write[packed] := read[packed]
      expect ValueError:
        update[packed] += read[packed]
      expect ValueError:
        discard 2.0 * read[packed]
      expect ValueError:
        discard read[packed] == read[packed]
      expect ValueError:
        discard read[scalar].re
      expect ValueError:
        discard read[scalar].im
