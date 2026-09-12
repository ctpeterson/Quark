#[
Lattice conformance

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

## Lattice geometry, layout, and domain contracts
## ==============================================
##
## This module describes the geometry and site selection to which Fields and
## Site Indices belong. A Lattice owns its Geometry and resolved Layout; Fields
## are separate values associated with that Lattice. Geometry, rank partitioning,
## packing, and the selected Domain remain stable while those associations exist.
##
## ``Geometry`` exposes the number of directions through ``len``, each extent
## through indexing, and the total number of sites through ``volume``.
## ``Partition`` exposes one factor per direction and its total ``partitions``.
## A ``Lattice`` exposes the global Geometry, the rank-local Geometry and Rank
## Partition, and the Packed Geometry and Packed Partition. The selected backend
## constructs and validates its native layout; these portable contracts describe
## what callers can observe without specifying another layout implementation.
##
## ``Domain`` identifies Full, EvenParity, or OddParity selection.
## ``Decomposition`` classifies the selection rule: Full has NoDecomposition,
## while either parity has SiteParity. A selected subset is itself a Lattice,
## with its own site organization and its original source association. Full
## Lattices support direct construction and parity selection; derived Lattices
## need not implement the Full constructor or recursively offer every selector.
##
## Conformability requires the same Domain kind and shared Geometry and resolved
## Layout instances. Equal dimensions, equal extents, or equal partition factors
## alone do not make independently constructed Lattices conformable. Copies and
## equivalent selections may retain that association. Fields and Site Indices
## use it to determine whether access or assignment is meaningful.
##
## The portable ``volume`` helper reads a Lattice's Geometry volume, and
## ``directions`` yields its zero-based direction numbers. These queries describe
## the lattice; they do not enumerate sites or select an execution placement.
## Site traversal belongs to the iteration module, and scoped placement belongs
## to the execution module.
##
## Concept matching establishes the required signatures and associated types.
## It does not prove instance provenance, correct site coverage, or native layout
## construction. Adapters connect the interface to existing backend facilities;
## observable and generated-code tests establish those additional properties.


type
  Decomposition* = enum
    ## Classifies the rule underlying a Lattice's domain selection.
    NoDecomposition = 0 ## Exactly as it says
    SiteParity =      1 ## Even/odd (red/black) checkerboard decomposition

  Domain* = enum
    ## Classifies a Lattice's immutable site selection, independently of origin.
    Full =       0 ## Full site selection, with no decomposition.
    EvenParity = 1 ## Even-parity site selection, with a SiteParity decomposition.
    OddParity =  2 ## Odd-parity site selection, with a SiteParity decomposition.

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
    ## does not own its Fields. `domain` is available at compile time; only Full
    ## requires direct construction through `newLattice`. Derived Lattices
    ## retain their source association and their own resolved site organization.
    ## Full also provides parity selection returning Lattices of the requested
    ## kinds; unsupported selections must reject explicitly.
    ## `conformable` compares kind and shared Geometry and Layout instances.
    ## This concept checks the operation for one concrete type; adapter
    ## conformance checks additionally exercise pairs of different types.
    lattice.domain is Domain

    lattice.geometry is Geometry

    lattice.rankGeometry is Geometry
    lattice.rankPartition is Partition

    lattice.packedGeometry is Geometry
    lattice.packedPartition is Partition

    lattice.dimensions is int

    conformable(lattice, lattice) is bool

    when lattice.domain == Full:
      mixin newLattice
      newLattice([1, 1, 1, 1]) is type(lattice) # partitions inferred by backend
      newLattice(
        [1, 1, 1, 1],
        rankPartition = [1, 1, 1, 1],
        packedPartition = [1, 1, 1, 1]
      ) is type(lattice)

      # Qualify selectors to avoid enum ambiguity during concept matching
      mixin newSublattice
      lattice.newSublattice(Domain.EvenParity) is Lattice
      lattice.newSublattice(Domain.OddParity) is Lattice
      lattice.newSublattice(Domain.EvenParity).domain == Domain.EvenParity
      lattice.newSublattice(Domain.OddParity).domain == Domain.OddParity

func decomposition*(lattice: Lattice): Decomposition =
  return case lattice.domain:
    of Full: NoDecomposition
    of EvenParity, OddParity: SiteParity

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

    BasicLayout = ref object
      rankPartitionData: BasicPartition
      rankGeometryData: BasicGeometry
      packedPartitionData: BasicPartition
      packedGeometryData: BasicGeometry

    BasicLattice[K: static Domain] = object
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

  proc geometry[K](lattice: BasicLattice[K]): BasicGeometry =
    lattice.geometryData

  template domain[K](lattice: BasicLattice[K]): Domain = K

  func conformable[KA, KB: static Domain](
    a: BasicLattice[KA]; b: BasicLattice[KB]
  ): bool =
    # This fixture's Layout instance identifies the entire construction.
    when KA != KB: false
    else: a.layoutData == b.layoutData

  func newSublattice(
    source: BasicLattice[Full]; selection: static Domain
  ): BasicLattice[selection] =
    when selection == Full: source
    else: raise newException(ValueError, "fixture does not implement parity storage")

  func dimensions[K](lattice: BasicLattice[K]): int =
    lattice.geometry.len

  proc layout[K](lattice: BasicLattice[K]): BasicLayout =
    lattice.layoutData

  proc rankPartition[K](lattice: BasicLattice[K]): BasicPartition =
    lattice.layout.rankPartition

  proc rankGeometry[K](lattice: BasicLattice[K]): BasicGeometry =
    lattice.layout.rankGeometry

  proc packedPartition[K](lattice: BasicLattice[K]): BasicPartition =
    lattice.layout.packedPartition

  proc packedGeometry[K](lattice: BasicLattice[K]): BasicGeometry =
    lattice.layout.packedGeometry

  proc geometry(lattice: GeometryOnly): BasicGeometry =
    lattice.geometryData

  proc newLattice(
    latticeExtents: openArray[int];
    rankPartition: openArray[int] = [];
    packedPartition: openArray[int] = []
  ): BasicLattice[Full] =
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

    BasicLattice[Full](
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

  suite "lattice basics":
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

  suite "portable lattice helpers":
    test "Full has no decomposition":
      check newLattice([4, 6]).decomposition == NoDecomposition

    test "Even and Odd have SiteParity decomposition":
      let full = newLattice([4, 6])
      let even = BasicLattice[EvenParity](geometryData: full.geometryData, layoutData: full.layoutData)
      let odd = BasicLattice[OddParity](geometryData: full.geometryData, layoutData: full.layoutData)
      check even.decomposition == SiteParity
      check odd.decomposition == SiteParity

    test "volume uses global geometry despite rank and packed partitions":
      let lattice = newLattice([8, 12], [2, 3], [2, 2])
      check lattice.volume == 96
      check lattice.rankGeometry.volume == 16
      check lattice.packedGeometry.volume == 4

    test "derived lattice volume uses its own geometry":
      let full = newLattice([8, 12])
      let selected = BasicLattice[EvenParity](
        geometryData: BasicGeometry(extents: @[4, 12]), layoutData: full.layoutData)
      check selected.volume == 48

    test "unit extents preserve volume":
      check newLattice([1, 7, 1]).volume == 7
      check newLattice([1]).volume == 1

    test "directions are ordered and zero based":
      check toSeq(newLattice([2]).directions) == @[0]
      check toSeq(newLattice([2, 3, 4]).directions) == @[0, 1, 2]
      check toSeq(newLattice([2, 2, 2, 2, 2, 2]).directions) == @[0, 1, 2, 3, 4, 5]

    test "directions depend on dimension count, not partition factors":
      check toSeq(newLattice([8, 12], [2, 3], [2, 2]).directions) == @[0, 1]

    test "derived lattices expose their own directions":
      let selected = BasicLattice[OddParity](geometryData: BasicGeometry(extents: @[4, 6, 8]))
      check toSeq(selected.directions) == @[0, 1, 2]

    test "direction iterators restart independently":
      let lattice = newLattice([4, 6])
      var pairs: seq[(int, int)]
      for i in lattice.directions:
        for j in lattice.directions: pairs.add (i, j)
      check pairs == @[(0, 0), (0, 1), (1, 0), (1, 1)]

    test "portable helpers reject non-lattices":
      check not compiles(decomposition(3))
      check not compiles(volume(GeometryOnly()))
      check not compiles(block:
        for direction in directions(@[2, 3]): discard direction)

  suite "structural lattice classification":
    test "geometry and partition have distinct required operations":
      check BasicGeometry is Geometry
      check BasicGeometry isnot Partition
      check BasicPartition is Partition
      check BasicPartition isnot Geometry

    test "all domain kinds satisfy the same lattice interface":
      check BasicLattice[Full] is Lattice
      check BasicLattice[EvenParity] is Lattice
      check BasicLattice[OddParity] is Lattice

    test "geometry alone does not establish lattice conformance":
      check GeometryOnly isnot Lattice
      check AccidentalLattice isnot Lattice

    test "ordinary sequences are neither Geometry nor Partition":
      check seq[int] isnot Geometry
      check seq[int] isnot Partition

  # Mutate one signature at a time so rejection identifies a required operation.
  type
    ShapeDefect = enum
      shapeValid, missingLength, nonIntegerLength, missingExtent, nonIntegerExtent,
      missingVolume, nonIntegerVolume, missingPartitions, nonIntegerPartitions
    ShapeWitness[F: static ShapeDefect] = object
  func len[F](value: ShapeWitness[F]): auto =
    when F == missingLength: {.error: "length unavailable".}
    elif F == nonIntegerLength: 2.0
    else: 2
  func `[]`[F](value: ShapeWitness[F]; direction: int): auto =
    when F == missingExtent: {.error: "indexing unavailable".}
    elif F == nonIntegerExtent: "extent"
    else: 4
  func volume[F](value: ShapeWitness[F]): auto =
    when F == missingVolume: {.error: "volume unavailable".}
    elif F == nonIntegerVolume: 16.0
    else: 16
  func partitions[F](value: ShapeWitness[F]): auto =
    when F == missingPartitions: {.error: "partition count unavailable".}
    elif F == nonIntegerPartitions: 16.0
    else: 16

  suite "Geometry and Partition signature rejection":
    test "one representation may satisfy both interfaces":
      check ShapeWitness[shapeValid] is Geometry
      check ShapeWitness[shapeValid] is Partition

    test "length is required for both interfaces":
      check ShapeWitness[missingLength] isnot Geometry
      check ShapeWitness[missingLength] isnot Partition

    test "length must return an integer":
      check ShapeWitness[nonIntegerLength] isnot Geometry
      check ShapeWitness[nonIntegerLength] isnot Partition

    test "direction indexing is required for both interfaces":
      check ShapeWitness[missingExtent] isnot Geometry
      check ShapeWitness[missingExtent] isnot Partition

    test "direction indexing must return an integer":
      check ShapeWitness[nonIntegerExtent] isnot Geometry
      check ShapeWitness[nonIntegerExtent] isnot Partition

    test "Geometry requires volume independently of partition count":
      check ShapeWitness[missingVolume] isnot Geometry
      check ShapeWitness[missingVolume] is Partition

    test "Geometry volume must return an integer":
      check ShapeWitness[nonIntegerVolume] isnot Geometry
      check ShapeWitness[nonIntegerVolume] is Partition

    test "Partition requires its count independently of volume":
      check ShapeWitness[missingPartitions] isnot Partition
      check ShapeWitness[missingPartitions] is Geometry

    test "Partition count must return an integer":
      check ShapeWitness[nonIntegerPartitions] isnot Partition
      check ShapeWitness[nonIntegerPartitions] is Geometry
