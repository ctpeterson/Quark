#[
Lattice concept

src: quark/base/lattice.nim
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
  Geometry* = concept geometry
    ## A finite logical index space with an extent in each direction
    ##
    ## `len` is the number of directions, indexing accesses an extent, and
    ## `volume` is the product of all extents. Every extent is positive. A
    ## Geometry may describe a complete Lattice or the result of applying a
    ## Partition.
    geometry.len is int
    geometry.volume is int
    geometry[0] is int

  Partition* = concept partition
    ## A rule that splits a source Geometry into indexed parts
    ##
    ## Indexing yields the factor for a source-Geometry direction, and
    ## `partitions` is the total number of resulting parts. Applying a
    ## Partition to a compatible Geometry produces a resulting Geometry.
    partition.len is int
    partition.partitions is int
    partition[0] is int

  Lattice* = concept lattice
    ## A finite site space with a Geometry and Partition for rank and packing
    ##
    ## `dimensions` is the number of Geometry directions, `directions`
    ## traverses them, and `volume` is the Geometry volume. Its Geometry and
    ## resolved rank and packed partitioning remain stable for the lifetime of
    ## the Lattice because Fields and Site Indices depend on them. A Lattice
    ## does not own its Fields.
    lattice.geometry is Geometry

    lattice.rankGeometry is Geometry
    lattice.rankPartition is Partition

    lattice.packedGeometry is Geometry
    lattice.packedPartition is Partition

    lattice.dimensions is int

    mixin newLattice
    newLattice([1, 1, 1, 1]) is type(lattice) # partitions inferred by backend
    newLattice(
      [1, 1, 1, 1],
      rankPartition = [1, 1, 1, 1],
      packedPartition = [1, 1, 1, 1]
    ) is type(lattice)

func volume*(lattice: Lattice): int =
  ## Returns the total number of sites in Lattice
  mixin volume
  lattice.geometry.volume

iterator directions*(lattice: Lattice): int =
  ## Returns an iterator over the directions of Lattice
  mixin dimensions
  for direction in 0..<lattice.dimensions: yield direction

when isMainModule:
  import std/[sequtils, unittest]

  type
    BasicGeometry = object
      extents: seq[int]

    BasicPartition = object
      factors: seq[int]

    BasicLayout = object
      rankPartitionData: BasicPartition
      rankGeometryData: BasicGeometry
      packedPartitionData: BasicPartition
      packedGeometryData: BasicGeometry

    BasicLattice = object
      geometryData: BasicGeometry
      layoutData: BasicLayout

    GeometryOnly = object
      geometryData: BasicGeometry

    AccidentalLattice = tuple[
      geometry: seq[int],
      layout: seq[seq[int]]
    ]

  func len(geometry: BasicGeometry): int =
    geometry.extents.len

  func `[]`(geometry: BasicGeometry; direction: int): int =
    geometry.extents[direction]

  func volume(geometry: BasicGeometry): int =
    result = 1
    for extent in geometry.extents:
      result *= extent

  func len(partition: BasicPartition): int =
    partition.factors.len

  func `[]`(partition: BasicPartition; direction: int): int =
    partition.factors[direction]

  func partitions(partition: BasicPartition): int =
    result = 1
    for factor in partition.factors:
      result *= factor

  func `/`(
    geometry: BasicGeometry;
    partition: BasicPartition
  ): BasicGeometry =
    for direction in 0..<geometry.len:
      result.extents.add(
        geometry[direction] div partition[direction]
      )

  func rankPartition(layout: BasicLayout): BasicPartition =
    layout.rankPartitionData

  func rankGeometry(layout: BasicLayout): BasicGeometry =
    layout.rankGeometryData

  func packedPartition(layout: BasicLayout): BasicPartition =
    layout.packedPartitionData

  func packedGeometry(layout: BasicLayout): BasicGeometry =
    layout.packedGeometryData

  proc geometry(lattice: BasicLattice): BasicGeometry =
    lattice.geometryData

  func dimensions(lattice: BasicLattice): int =
    lattice.geometry.len

  proc layout(lattice: BasicLattice): BasicLayout =
    lattice.layoutData

  proc rankPartition(lattice: BasicLattice): BasicPartition =
    lattice.layout.rankPartition

  proc rankGeometry(lattice: BasicLattice): BasicGeometry =
    lattice.layout.rankGeometry

  proc packedPartition(lattice: BasicLattice): BasicPartition =
    lattice.layout.packedPartition

  proc packedGeometry(lattice: BasicLattice): BasicGeometry =
    lattice.layout.packedGeometry

  proc geometry(lattice: GeometryOnly): BasicGeometry =
    lattice.geometryData

  proc newLattice(
    latticeExtents: openArray[int];
    rankPartition: openArray[int] = [];
    packedPartition: openArray[int] = []
  ): BasicLattice =
    let geometry = BasicGeometry(extents: @latticeExtents)
    let resolvedRankPartition = if rankPartition.len == 0:
      BasicPartition(factors: newSeqWith(geometry.len, 1))
    else:
      BasicPartition(factors: @rankPartition)
    let rankGeometry = geometry / resolvedRankPartition
    let resolvedPackedPartition = if packedPartition.len == 0:
      BasicPartition(factors: newSeqWith(rankGeometry.len, 1))
    else:
      BasicPartition(factors: @packedPartition)
    let packedGeometry = rankGeometry / resolvedPackedPartition

    BasicLattice(
      geometryData: geometry,
      layoutData: BasicLayout(
        rankPartitionData: resolvedRankPartition,
        rankGeometryData: rankGeometry,
        packedPartitionData: resolvedPackedPartition,
        packedGeometryData: packedGeometry
      )
    )

  static:
    doAssert BasicGeometry is Geometry
    doAssert BasicPartition is Partition
    doAssert typeof(newLattice(
      [8, 8, 8, 16],
      [2, 1, 1, 2],
      [1, 2, 2, 1]
    )) is Lattice
    doAssert not (GeometryOnly is Lattice)
    doAssert not (AccidentalLattice is Lattice)
    doAssert not (seq[int] is Geometry)
    doAssert not (seq[int] is Partition)
    doAssert not (int is Lattice)

  suite "smoke tests":
    test "partitions produce the rank and packed geometries":
      let lattice: Lattice = newLattice(
        [8, 8, 8, 16],
        [2, 1, 1, 2],
        [1, 2, 2, 1]
      )

      check lattice.geometry[0] == 8
      check lattice.geometry[3] == 16
      check lattice.rankPartition[0] == 2
      check lattice.rankPartition[3] == 2
      check lattice.rankGeometry[0] == 4
      check lattice.rankGeometry[3] == 8
      check lattice.packedPartition[1] == 2
      check lattice.packedGeometry[1] == 4
      check lattice.rankGeometry ==
        lattice.geometry / lattice.rankPartition
      check lattice.packedGeometry ==
        lattice.rankGeometry / lattice.packedPartition

      var directions: seq[int]
      for direction in lattice.directions:
        directions.add direction
      check directions == @[0, 1, 2, 3]

    test "omitted partitions are inferred":
      let rankSpecified: Lattice = newLattice(
        [8, 8, 8, 16],
        rankPartition = [2, 1, 1, 2]
      )
      check rankSpecified.rankPartition[0] == 2
      check rankSpecified.packedPartition.partitions == 1

      let packedSpecified: Lattice = newLattice(
        [8, 8, 8, 16],
        packedPartition = [1, 2, 2, 1]
      )
      check packedSpecified.rankPartition.partitions == 1
      check packedSpecified.packedPartition[1] == 2
