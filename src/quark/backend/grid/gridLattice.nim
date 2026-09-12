#[
Grid Lattice implementation

This is sketch work for Milestone 1 that should not be taken as a final
implementation. Once the implementation is finalized (Milestone 2), this notice must
be permanently removed.

src: quark/backend/grid/gridLattice.nim
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

import quark/base/[lattice]

type
  GridGeometry {.requiresInit.} = ref object
    extentsData: seq[int]
    volumeData: int

  GridPartition {.requiresInit.} = object
    factorsData: seq[int]
    partitionsData: int

  GridLayout {.requiresInit.} = ref object
    rankPartitionData: GridPartition
    rankGeometryData: GridGeometry
    packedPartitionData: GridPartition
    packedGeometryData: GridGeometry

  GridLattice[K: static Domain] {.requiresInit.} = object
    geometryData: GridGeometry
    layoutData: GridLayout

proc newGeometry*(extents: openArray[int]): GridGeometry =
  if extents.len == 0:
    raise newException(ValueError, "a Geometry requires at least one extent")

  var validatedExtents = newSeqOfCap[int](extents.len)
  var volume = 1

  for direction, extent in extents:
    if extent <= 0:
      raise newException(
        ValueError,
        "Geometry extent " & $direction & " must be positive"
      )
    if volume > high(int) div extent:
      raise newException(ValueError, "Geometry volume exceeds int capacity")

    validatedExtents.add extent
    volume *= extent

  GridGeometry(extentsData: validatedExtents, volumeData: volume)

func len*(geometry: GridGeometry): int =
  geometry.extentsData.len

func `[]`*(geometry: GridGeometry; direction: int): int =
  geometry.extentsData[direction]

func volume*(geometry: GridGeometry): int =
  geometry.volumeData

func `==`*(a, b: GridGeometry): bool =
  a.extentsData == b.extentsData

proc newPartition*(factors: openArray[int]): GridPartition =
  if factors.len == 0:
    raise newException(ValueError, "a Partition requires at least one factor")

  var validatedFactors = newSeqOfCap[int](factors.len)
  var partitions = 1

  for direction, factor in factors:
    if factor <= 0:
      raise newException(
        ValueError,
        "Partition factor " & $direction & " must be positive"
      )
    if partitions > high(int) div factor:
      raise newException(
        ValueError,
        "Partition count exceeds int capacity"
      )

    validatedFactors.add factor
    partitions *= factor

  GridPartition(
    factorsData: validatedFactors,
    partitionsData: partitions
  )

func len*(partition: GridPartition): int =
  partition.factorsData.len

func `[]`*(partition: GridPartition; direction: int): int =
  partition.factorsData[direction]

func partitions*(partition: GridPartition): int =
  partition.partitionsData

func `==`*(a, b: GridPartition): bool =
  a.factorsData == b.factorsData

proc `/`*(
  geometry: GridGeometry;
  partition: GridPartition
): GridGeometry =
  if geometry.len != partition.len:
    raise newException(
      ValueError,
      "a Partition must have one factor per Geometry direction"
    )

  var partitionedExtents = newSeqOfCap[int](geometry.len)

  for direction in 0..<geometry.len:
    let extent = geometry[direction]
    let factor = partition[direction]
    if extent mod factor != 0:
      raise newException(
        ValueError,
        "Geometry extent " & $direction &
          " is not divisible by Partition factor " & $factor
      )

    partitionedExtents.add extent div factor

  newGeometry(partitionedExtents)

proc unitPartition(geometry: GridGeometry): GridPartition =
  var factors = newSeq[int](geometry.len)
  for factor in factors.mitems:
    factor = 1
  newPartition(factors)

proc inferRankPartition(geometry: GridGeometry): GridPartition =
  unitPartition(geometry)

proc inferPackedPartition(geometry: GridGeometry): GridPartition =
  unitPartition(geometry)

proc newLattice*(
  latticeGeometry: GridGeometry;
  rankPartition: GridPartition;
  packedPartition: GridPartition
): GridLattice[Full] =
  let rankGeometry = latticeGeometry / rankPartition
  let packedGeometry = rankGeometry / packedPartition

  GridLattice[Full](
    geometryData: latticeGeometry,
    layoutData: GridLayout(
      rankPartitionData: rankPartition,
      rankGeometryData: rankGeometry,
      packedPartitionData: packedPartition,
      packedGeometryData: packedGeometry
    )
  )

proc newLattice*(
  latticeExtents: openArray[int];
  rankPartition: openArray[int] = [];
  packedPartition: openArray[int] = []
): GridLattice[Full] =
  let latticeGeometry = newGeometry(latticeExtents)
  let resolvedRankPartition = if rankPartition.len == 0:
    inferRankPartition(latticeGeometry)
  else:
    newPartition(rankPartition)
  let rankGeometry = latticeGeometry / resolvedRankPartition
  let resolvedPackedPartition = if packedPartition.len == 0:
    inferPackedPartition(rankGeometry)
  else:
    newPartition(packedPartition)

  newLattice(
    latticeGeometry,
    resolvedRankPartition,
    resolvedPackedPartition
  )

func geometry*[K](lattice: GridLattice[K]): GridGeometry =
  lattice.geometryData

func dimensions*[K](lattice: GridLattice[K]): int =
  lattice.geometry.len

func rankPartition*[K](lattice: GridLattice[K]): GridPartition =
  lattice.layoutData.rankPartitionData

func rankGeometry*[K](lattice: GridLattice[K]): GridGeometry =
  lattice.layoutData.rankGeometryData

func packedPartition*[K](lattice: GridLattice[K]): GridPartition =
  lattice.layoutData.packedPartitionData

func packedGeometry*[K](lattice: GridLattice[K]): GridGeometry =
  lattice.layoutData.packedGeometryData

template domain*[K](lattice: GridLattice[K]): Domain = K

func conformable*[KA, KB: static Domain](
  a: GridLattice[KA]; b: GridLattice[KB]
): bool =
  ## Whether both Lattices have the same kind and share Geometry and Layout.
  when KA != KB:
    false
  else:
    system.`==`(a.geometryData, b.geometryData) and
      system.`==`(a.layoutData, b.layoutData)

func newSublattice*(
  lattice: GridLattice[Full]; selection: static Domain = Full
): GridLattice[selection] =
  when selection == Full:
    lattice
  else:
    raise newException(ValueError, "Grid parity Lattice derivation is not implemented")

when isMainModule:
  import std/[unittest]

  suite "Grid lattice adapter":
    test "partitions produce inspectable geometries":
      let lattice = newLattice(
        [8, 8, 8, 16],
        [2, 1, 1, 2],
        [1, 2, 2, 1]
      )

      check lattice.geometry == newGeometry([8, 8, 8, 16])
      check lattice.rankPartition == newPartition([2, 1, 1, 2])
      check lattice.rankGeometry == newGeometry([4, 8, 8, 8])
      check lattice.packedPartition == newPartition([1, 2, 2, 1])
      check lattice.packedGeometry == newGeometry([4, 4, 4, 8])

    test "construction copies its inputs":
      var extents = @[8, 8, 8, 16]
      var rankFactors = @[2, 1, 1, 2]
      var packedFactors = @[1, 2, 2, 1]
      let lattice = newLattice(extents, rankFactors, packedFactors)

      extents[0] = 4
      rankFactors[0] = 1
      packedFactors[1] = 1

      check lattice.geometry[0] == 8
      check lattice.rankPartition[0] == 2
      check lattice.packedPartition[1] == 2

    test "omitted partitions are inferred":
      let rankSpecified = newLattice(
        [8, 8, 8, 16],
        rankPartition = [2, 1, 1, 2]
      )
      check rankSpecified.rankPartition[0] == 2
      check rankSpecified.packedPartition.partitions == 1

      let packedSpecified = newLattice(
        [8, 8, 8, 16],
        packedPartition = [1, 2, 2, 1]
      )
      check packedSpecified.rankPartition.partitions == 1
      check packedSpecified.packedPartition[1] == 2

    test "invalid geometries and partitions reject explicitly":
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

static: # Adapter conformance is checked on every import.
  doAssert GridGeometry is Geometry
  doAssert GridPartition is Partition
  template assertFullConstruction(expression: untyped) =
    doAssert typeof(expression) is Lattice
    doAssert expression.domain == Full

  assertFullConstruction(newLattice([8, 8, 8, 16]))
  assertFullConstruction(newLattice(
    [8, 8, 8, 16],
    rankPartition = [2, 1, 1, 2],
    packedPartition = [1, 2, 2, 1]
  ))
  assertFullConstruction(newLattice(
    [8, 8, 8, 16], rankPartition = [2, 1, 1, 2]
  ))
  assertFullConstruction(newLattice(
    [8, 8, 8, 16], packedPartition = [1, 2, 2, 1]
  ))
  assertFullConstruction(newLattice(
    newGeometry([8, 8, 8, 16]),
    newPartition([2, 1, 1, 2]),
    newPartition([1, 2, 2, 1])
  ))
