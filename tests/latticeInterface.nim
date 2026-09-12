import std/unittest

import quark

static:
  doAssert not (seq[int] is Geometry)
  doAssert not (seq[int] is Partition)
  doAssert not declared(QexGeometry)
  doAssert not declared(QexPartition)
  doAssert not declared(QexLayout)
  doAssert not declared(QexLattice)
  doAssert not declared(GridGeometry)
  doAssert not declared(GridPartition)
  doAssert not declared(GridLayout)
  doAssert not declared(GridLattice)

suite "portable lattice interface":
  test "a Lattice exposes each Partition and resulting Geometry":
    let geometry: Geometry = newGeometry([8, 8, 8, 16])
    let rankPartition: Partition = newPartition([2, 1, 1, 2])
    let packedPartition: Partition = newPartition([1, 2, 2, 1])
    let lattice: Lattice = newLattice(
      geometry,
      rankPartition,
      packedPartition
    )
    static:
      doAssert lattice.domain == Full

    check lattice.dimensions == 4
    check lattice.volume == 8192
    check lattice.geometry.len == 4
    check lattice.geometry[3] == 16
    check lattice.geometry.volume == 8192

    var directions: seq[int]
    for direction in lattice.directions:
      directions.add direction
    check directions == @[0, 1, 2, 3]

    check lattice.rankPartition[0] == 2
    check lattice.rankPartition[3] == 2
    check lattice.rankPartition.partitions == 4
    check lattice.rankGeometry == newGeometry([4, 8, 8, 8])
    check lattice.rankGeometry == lattice.geometry / lattice.rankPartition

    check lattice.packedPartition[1] == 2
    check lattice.packedPartition.partitions == 4
    check lattice.packedGeometry == newGeometry([4, 4, 4, 8])
    check lattice.packedGeometry ==
      lattice.rankGeometry / lattice.packedPartition

  test "the constructor delegates omitted partitions to the backend":
    let lattice: Lattice = newLattice([8, 8, 8, 16])
    static:
      doAssert lattice.domain == Full

    check lattice.rankPartition.partitions == 1
    check lattice.rankGeometry == lattice.geometry
    check lattice.packedPartition.partitions == 1
    check lattice.packedGeometry == lattice.rankGeometry

    let rankSpecified: Lattice = newLattice(
      [8, 8, 8, 16],
      rankPartition = [2, 1, 1, 2]
    )
    static:
      doAssert rankSpecified.domain == Full
    check rankSpecified.rankPartition[0] == 2
    check rankSpecified.rankGeometry == newGeometry([4, 8, 8, 8])
    check rankSpecified.packedPartition.partitions == 1
    check rankSpecified.packedGeometry == rankSpecified.rankGeometry

    let packedSpecified: Lattice = newLattice(
      [8, 8, 8, 16],
      packedPartition = [1, 2, 2, 1]
    )
    static:
      doAssert packedSpecified.domain == Full
    check packedSpecified.rankPartition.partitions == 1
    check packedSpecified.rankGeometry == packedSpecified.geometry
    check packedSpecified.packedPartition[1] == 2
    check packedSpecified.packedGeometry == newGeometry([8, 4, 4, 16])

    let bothSpecified: Lattice = newLattice(
      [8, 8, 8, 16],
      rankPartition = [2, 1, 1, 2],
      packedPartition = [1, 2, 2, 1]
    )
    static:
      doAssert bothSpecified.domain == Full
    check bothSpecified.rankGeometry == newGeometry([4, 8, 8, 8])
    check bothSpecified.packedGeometry == newGeometry([4, 4, 4, 8])

  test "unsupported geometry and regular partitions reject explicitly":
    expect ValueError:
      discard newGeometry([])
    expect ValueError:
      discard newGeometry([8, 0, 8, 16])
    expect ValueError:
      discard newGeometry([high(int), 2])
    expect ValueError:
      discard newPartition([])
    expect ValueError:
      discard newPartition([1, -1, 1, 1])
    expect ValueError:
      discard newPartition([high(int), 2])
    expect ValueError:
      discard newLattice([8, 8], [2], [1, 1])
    expect ValueError:
      discard newLattice([8, 8], [3, 1], [1, 1])
    expect ValueError:
      discard newLattice([8, 8], [2, 1], [3, 1])
