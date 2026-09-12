# Geometry and iteration oracle for Milestone 2 Step 2.
# The backend constructs and validates its native layout. This oracle checks
# the metadata and iteration that Quark exposes, without reproducing that logic.

import std/sets
import quark

quark:
  let lattice: Lattice = [8, 8, 8, 16].newLattice()
  doAssert lattice.domain == Full
  doAssert lattice.dimensions == 4
  doAssert lattice.volume == 8192
  var directions: seq[int]
  for mu in lattice.directions:
    directions.add mu
    doAssert lattice.geometry[mu] == [8, 8, 8, 16][mu]
  doAssert directions == @[0, 1, 2, 3]

  let copied = lattice
  let full = lattice.newSublattice(Full)
  doAssert conformable(lattice, copied)
  doAssert conformable(lattice, full)

  # Indices need not match between granularities, ranks, or backend layouts.
  # Each iterator must nevertheless enumerate its own rank-local space once.
  var scalarIndices, packedIndices: HashSet[int]
  for n in lattice.sites(Scalar):
    static: doAssert n is ScalarSite[typeof(lattice)]
    doAssert conformable(n.lattice, lattice)
    doAssert n.index notin scalarIndices
    scalarIndices.incl n.index
  for n in lattice.sites(Packed):
    static: doAssert n is PackedSite[typeof(lattice)]
    doAssert conformable(n.lattice, lattice)
    doAssert n.index notin packedIndices
    packedIndices.incl n.index
  doAssert scalarIndices.len == lattice.rankGeometry.volume
  doAssert packedIndices.len == lattice.packedGeometry.volume

  var repeated: HashSet[int]
  for n in copied.sites(Scalar): repeated.incl n.index
  doAssert repeated == scalarIndices

  # Parity construction is a geometry capability at this step; parity Fields
  # are exercised later by Oracle B. Site selection is performed by the backend.
  let even = lattice.newSublattice(EvenParity)
  let odd = lattice.newSublattice(OddParity)
  doAssert even.domain == EvenParity
  doAssert odd.domain == OddParity
  doAssert even.volume + odd.volume == lattice.volume
  doAssert conformable(even, lattice.newSublattice(EvenParity))
  doAssert conformable(odd, lattice.newSublattice(OddParity))
  var evenIndices, oddIndices: HashSet[int]
  for n in even.sites(Scalar):
    doAssert conformable(n.lattice, even)
    doAssert n.index notin evenIndices
    evenIndices.incl n.index
  for n in odd.sites(Scalar):
    doAssert conformable(n.lattice, odd)
    doAssert n.index notin oddIndices
    oddIndices.incl n.index
  doAssert evenIndices.len + oddIndices.len == scalarIndices.len
