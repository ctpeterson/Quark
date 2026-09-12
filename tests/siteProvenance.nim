import std/unittest
import quark
include support/siteIndices

static:
  type Even = typeof(newLattice([8, 8]).newSublattice(EvenParity))
  type Odd = typeof(newLattice([8, 8]).newSublattice(OddParity))
  doAssert compiles(block:
    within Host:
      let view = default(Field[Real[D], Even]).view(Read)
      discard view[default(ScalarSite[Even])]
      discard view[default(PackedSite[Even])])
  doAssert not compiles(block:
    within Host:
      let field = newLattice([8, 8]).newField(Real[D])
      let view = field.view(Read)
      discard view[default(ScalarSite[Even])])
  doAssert not compiles(block:
    within Host:
      let field = default(Field[Real[D], Odd])
      let view = field.view(Read)
      discard view[default(PackedSite[Even])])
  doAssert not compiles(ScalarIndex(indexData: 0))
  doAssert not compiles(PackedIndex(indexData: 0))

suite "Site Index Lattice provenance":
  test "copies and Full selections remain conformable":
    let lattice = newLattice([8, 8])
    let copied = lattice
    let field = copied.newSublattice(Full).newField(Real[D])
    within Host:
      let view = field.view(Read)
      discard view[firstScalar(lattice)]
      discard view[firstPacked(lattice)]

  test "incompatible extents and equal but independent instances reject":
    let source = newLattice([8, 8])
    for other in [newLattice([4, 4]), newLattice([8, 8])]:
      let field = other.newField(Real[D])
      within Host:
        let view = field.view(Read)
        expect ValueError: discard view[firstScalar(source)]
        expect ValueError: discard view[firstPacked(source)]

  test "a shared Geometry with independent Layout still rejects":
    let geometry = newGeometry([8, 8])
    let unit = newPartition([1, 1])
    let a = newLattice(geometry, unit, unit)
    let b = newLattice(geometry, unit, unit)
    within Accelerator:
      let view = b.newField(Real[D]).view(Read)
      expect ValueError: discard view[firstScalar(a)]
      expect ValueError: discard view[firstPacked(a)]

  test "index metadata cannot be rewritten or an empty index used":
    let lattice = newLattice([8, 8])
    var site = firstScalar(lattice)
    static:
      doAssert not compiles(site.index = 3)
      doAssert not compiles(site.lattice = newLattice([4, 4]))
    within Host:
      let view = lattice.newField(Real[D]).view(Read)
      expect ValueError: discard view[default(ScalarIndex)]
