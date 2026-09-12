when not (defined(latticeMissingSelection) or defined(latticeWrongSelection)):
  import std/unittest
import quark/base/lattice

# Type-contract fixtures, independent of backend storage and numerical lowering.
type
  FixtureGeometry = object
  FixturePartition = object
  Instance = ref object
  FixtureLattice[K: static Domain; ConstructorMatches: static bool] = object
    geometryInstance, layoutInstance: Instance

func len(g: FixtureGeometry): int = 4
func volume(g: FixtureGeometry): int = 1
func `[]`(g: FixtureGeometry; i: int): int = 1
func len(p: FixturePartition): int = 4
func partitions(p: FixturePartition): int = 1
func `[]`(p: FixturePartition; i: int): int = 1

template domain[K, C](x: FixtureLattice[K, C]): Domain = K
func geometry[K, C](x: FixtureLattice[K, C]): FixtureGeometry = FixtureGeometry()
func rankGeometry[K, C](x: FixtureLattice[K, C]): FixtureGeometry = FixtureGeometry()
func packedGeometry[K, C](x: FixtureLattice[K, C]): FixtureGeometry = FixtureGeometry()
func rankPartition[K, C](x: FixtureLattice[K, C]): FixturePartition = FixturePartition()
func packedPartition[K, C](x: FixtureLattice[K, C]): FixturePartition = FixturePartition()
func dimensions[K, C](x: FixtureLattice[K, C]): int = 4

func conformable[KA, KB: static Domain; CA, CB: static bool](
  a: FixtureLattice[KA, CA]; b: FixtureLattice[KB, CB]
): bool =
  when KA != KB:
    false
  else:
    a.geometryInstance == b.geometryInstance and
      a.layoutInstance == b.layoutInstance

proc newLattice(
  extents: openArray[int]; rankPartition: openArray[int] = [];
  packedPartition: openArray[int] = []
): FixtureLattice[Full, true] =
  FixtureLattice[Full, true](
    geometryInstance: Instance(), layoutInstance: Instance())

when not defined(latticeMissingSelection):
  func newSublattice[C](
    source: FixtureLattice[Full, C]; selection: static Domain
  ): auto =
    when defined(latticeWrongSelection):
      # Both selectors return a valid Lattice, but EvenParity gets the wrong kind.
      FixtureLattice[OddParity, C](
        geometryInstance: source.geometryInstance,
        layoutInstance: source.layoutInstance)
    else:
      FixtureLattice[selection, C](
        geometryInstance: source.geometryInstance,
        layoutInstance: source.layoutInstance)

func compare[A: Lattice; B: Lattice](a: A; b: B): bool =
  mixin conformable
  conformable(a, b)

type UnrelatedLattice = object
template domain(x: UnrelatedLattice): Domain = EvenParity
func geometry(x: UnrelatedLattice): FixtureGeometry = FixtureGeometry()
func rankGeometry(x: UnrelatedLattice): FixtureGeometry = FixtureGeometry()
func packedGeometry(x: UnrelatedLattice): FixtureGeometry = FixtureGeometry()
func rankPartition(x: UnrelatedLattice): FixturePartition = FixturePartition()
func packedPartition(x: UnrelatedLattice): FixturePartition = FixturePartition()
func dimensions(x: UnrelatedLattice): int = 4
func conformable(a, b: UnrelatedLattice): bool = true

static:
  when defined(latticeMissingSelection) or defined(latticeWrongSelection):
    doAssert not (FixtureLattice[Full, true] is Lattice)
  else:
    doAssert FixtureLattice[Full, true] is Lattice
  doAssert FixtureLattice[EvenParity, true] is Lattice
  doAssert FixtureLattice[OddParity, true] is Lattice
  # Full requires a constructor returning the matched concrete type.
  doAssert not (FixtureLattice[Full, false] is Lattice)
  # The same missing constructor is permitted for derived kinds.
  doAssert FixtureLattice[EvenParity, false] is Lattice
  doAssert FixtureLattice[OddParity, false] is Lattice
  doAssert not (int is Lattice)
  doAssert UnrelatedLattice is Lattice
  # A same-type predicate does not establish an arbitrary cross-type operation.
  doAssert not compiles(compare(
    newLattice([1, 1, 1, 1]), UnrelatedLattice()))
  doAssert not compiles(compare(
    UnrelatedLattice(), newLattice([1, 1, 1, 1])))

when not (defined(latticeMissingSelection) or defined(latticeWrongSelection)):
  suite "Lattice type and construction contracts":
    test "Full derives distinct concrete types satisfying Lattice":
      let source: Lattice = newLattice([1, 1, 1, 1])
      let full: Lattice = source.newSublattice(Full)
      let even: Lattice = source.newSublattice(EvenParity)
      let odd: Lattice = source.newSublattice(OddParity)
      static:
        doAssert not (typeof(even) is typeof(full))
        doAssert not (typeof(odd) is typeof(even))
        doAssert full.domain == Full
        doAssert even.domain == EvenParity
        doAssert odd.domain == OddParity
        doAssert not compiles(even.newSublattice(OddParity))
      check full.decomposition == NoDecomposition
      check even.decomposition == SiteParity
      check odd.decomposition == SiteParity
      check compare(source, full)
      check compare(even, source.newSublattice(EvenParity))
      check compare(odd, source.newSublattice(OddParity))
      check not compare(full, even)
      check not compare(even, full)
      check not compare(full, odd)
      check not compare(odd, full)
      check not compare(even, odd)
      check not compare(odd, even)

    test "same-kind comparison retains both instance requirements":
      let source = newLattice([1, 1, 1, 1])
      let even = source.newSublattice(EvenParity)
      let otherGeometry = FixtureLattice[EvenParity, true](
        geometryInstance: Instance(), layoutInstance: even.layoutInstance)
      let otherLayout = FixtureLattice[EvenParity, true](
        geometryInstance: even.geometryInstance, layoutInstance: Instance())
      check not compare(even, otherGeometry)
      check not compare(otherGeometry, even)
      check not compare(even, otherLayout)
      check not compare(otherLayout, even)
