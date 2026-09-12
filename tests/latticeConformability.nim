import std/unittest
import quark

func compare[A: Lattice; B: Lattice](a: A; b: B): bool =
  mixin conformable
  conformable(a, b)

template acceptsBothOrders(A, B: typedesc) =
  static:
    doAssert compiles(block:
      func comparePair(a: A; b: B): bool =
        compare(a, b) and compare(b, a)
    )

suite "portable Lattice conformability":
  test "Full selection preserves the concrete Lattice and shared instances":
    let source = newLattice([8, 8, 8, 16], [2, 1, 1, 2], [1, 2, 2, 1])
    let full: Lattice = source.newSublattice(Full)
    let defaultFull: Lattice = source.newSublattice()
    static:
      doAssert typeof(full) is typeof(source)
      doAssert typeof(defaultFull) is Lattice
      doAssert full.domain == Full
    acceptsBothOrders(typeof(full), typeof(full.newSublattice(EvenParity)))
    acceptsBothOrders(typeof(full), typeof(full.newSublattice(OddParity)))
    acceptsBothOrders(typeof(full.newSublattice(EvenParity)), typeof(full.newSublattice(OddParity)))
    check full.volume == 8192
    check compare(source, full)
    check compare(full, source)
    check compare(defaultFull, full)
    check full.decomposition == NoDecomposition

  test "copies and repeated selection preserve conformability":
    let source = newLattice([8, 8])
    let copiedSource = source
    let a = source.newSublattice(Full)
    let b = copiedSource.newSublattice(Full)
    check compare(source, copiedSource)
    check compare(a, b)
    check compare(b, a)
    check compare(a, a)

  test "equal extents do not replace shared instances":
    let a = newLattice([8, 8])
    let b = newLattice([8, 8])
    check a.geometry == b.geometry
    check not compare(a, b)
    check not compare(b, a)

  test "a shared Geometry still requires the same resolved Layout":
    let geometry = newGeometry([8, 8])
    let unit = newPartition([1, 1])
    let packed = newPartition([2, 1])
    let a = newLattice(geometry, unit, unit)
    let equalLayout = newLattice(geometry, unit, unit)
    let differentLayout = newLattice(geometry, unit, packed)
    check not compare(a, equalLayout)
    check not compare(a, differentLayout)

  test "selection and source association cannot be reinterpreted":
    var full = newLattice([8, 8])
    static:
      doAssert not compiles(full.domain = EvenParity)
      doAssert not compiles(full.geometryData = newGeometry([8, 8]))
      doAssert not compiles(full.newSublattice(0))
      doAssert typeof(full.newSublattice(EvenParity)) is Lattice
      doAssert typeof(full.newSublattice(OddParity)) is Lattice

  test "unsupported parity derivation reports its missing implementation":
    let full = newLattice([8, 8])
    expect ValueError:
      discard full.newSublattice(EvenParity)
    expect ValueError:
      discard full.newSublattice(OddParity)
