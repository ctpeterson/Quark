#[
Iteration space conformance

src: quark/base/iteration.nim
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

## Typed site traversal and parallel execution intent
## ==================================================
##
## This module distinguishes Scalar and Packed iteration while retaining the
## Lattice from which each Site Index originates. ``ScalarSite[L]`` identifies
## one logical rank-local site. ``PackedSite[L]`` identifies one layout-defined
## group of scalar sites. ``Site[L]`` accepts either kind while keeping the
## associated Lattice type available to the type system.
##
## ``sites(lattice, Scalar)`` and ``sites(lattice, Packed)`` select an iteration
## space statically. Traversal applies to the Lattice's immutable Domain, whether
## Full or a derived selection. A Site Index is used directly to access a Field
## on a conformable Lattice; a raw integer cannot replace its kind and provenance.
## The ``lattice`` accessor retains the originating instance, while ``index``
## exposes the index within that granularity's resolved organization. That integer
## is not a portable global coordinate or a tensor-component/packing-lane index.
##
## Site Granularity determines the value obtained through Field access. A Scalar
## Site accesses one mathematical site value, and a Packed Site accesses the
## layout-packed group of those values. The site value may itself be numeric or
## tensor-valued; selecting a tensor component does not change Site Granularity.
##
## ``parallel for`` marks a Site Loop for the native parallel construct selected
## by its enclosing Execution Context. It requires ``within Host`` or
## ``within Accelerator`` and does not infer placement from Scalar or Packed.
## Both granularities are meaningful in both contexts when supported. A regular
## ``for`` remains an ordinary Nim traversal, useful for serial host setup and
## verification without introducing shared counters into a parallel loop.
##
## The portable contract preserves index kinds, source association, explicit
## placement, and explicit granularity. The backend supplies native traversal,
## packing, and parallel execution. Numerical coverage checks and inspection of
## generated constructs are needed to establish those behaviors; structural
## classification and successful macro expansion are not enough.


import std/[macros]

import lattice
import execution

type IterationSpace* = enum
  Scalar = 0 # single-site
  Packed = 1 # SIMD on CPU, coalesced memory access on GPU

type # we should marge ScalarSite and PackedSite into a unified Site type
  ScalarSite*[L] = object
    ## One scalar site, retaining its originating Lattice.
    indexData: int
    latticeData: L

  PackedSite*[L] = object
    ## One packed site, retaining its originating Lattice.
    indexData: int
    latticeData: L

  Site*[L] = ScalarSite[L] | PackedSite[L]

func lattice*[L](site: Site[L]): L = site.latticeData
func index*[L](site: Site[L]): int = site.indexData

iterator sites*[L: Lattice](lattice: L; space: static IterationSpace): auto =
  # Contract scaffold; native iteration and coverage belong to Milestone 2.
  when space == Scalar: yield ScalarSite[L](indexData: 0, latticeData: lattice)
  else: yield PackedSite[L](indexData: 0, latticeData: lattice)

macro parallel*(loop: untyped): untyped =
  assert loop.kind == nnkForStmt, "input to parallel macro must be a for loop"

  result = quote do:
    block:
      const placement {.used.} = executionSpace()
      `loop`

when isMainModule:
  import std/unittest

  # Signature witness for the portable contract; no native layout or storage.
  type
    TestGeometry = object
    TestPartition = object
    TestLattice[K: static Domain] = ref object
      identity: int

  func len(g: TestGeometry): int = 2
  func volume(g: TestGeometry): int = 24
  func `[]`(g: TestGeometry; i: int): int = [4, 6][i]
  func len(p: TestPartition): int = 2
  func partitions(p: TestPartition): int = 1
  func `[]`(p: TestPartition; i: int): int = 1
  template domain[K](l: TestLattice[K]): Domain = K
  func geometry[K](l: TestLattice[K]): TestGeometry = TestGeometry()
  func rankGeometry[K](l: TestLattice[K]): TestGeometry = TestGeometry()
  func packedGeometry[K](l: TestLattice[K]): TestGeometry = TestGeometry()
  func rankPartition[K](l: TestLattice[K]): TestPartition = TestPartition()
  func packedPartition[K](l: TestLattice[K]): TestPartition = TestPartition()
  func dimensions[K](l: TestLattice[K]): int = 2
  func conformable[A, B](a: TestLattice[A]; b: TestLattice[B]): bool =
    when A == B: a == b
    else: false

  suite "site indices":
    test "scalar accessor retains index and lattice identity":
      let origin = TestLattice[EvenParity](identity: 7)
      let site = ScalarSite[typeof(origin)](indexData: 19, latticeData: origin)
      check site.index == 19
      check site.lattice == origin

    test "packed accessor retains index and lattice identity":
      let origin = TestLattice[OddParity](identity: 8)
      let site = PackedSite[typeof(origin)](indexData: 5, latticeData: origin)
      check site.index == 5
      check site.lattice == origin

    test "copying an index retains its originating instance":
      let origin = TestLattice[EvenParity]()
      let site = ScalarSite[typeof(origin)](indexData: 3, latticeData: origin)
      let copied = site
      check copied.index == site.index
      check copied.lattice == origin
      check copied.lattice != TestLattice[EvenParity]()

    test "scalar and packed are distinct types in the Site union":
      check ScalarSite[TestLattice[EvenParity]] is Site
      check PackedSite[TestLattice[EvenParity]] is Site
      check ScalarSite[TestLattice[EvenParity]] isnot PackedSite[TestLattice[EvenParity]]
      check int isnot Site

    test "domain kind remains part of the index type":
      check ScalarSite[TestLattice[EvenParity]] isnot ScalarSite[TestLattice[OddParity]]
      check PackedSite[TestLattice[EvenParity]] isnot PackedSite[TestLattice[OddParity]]

  suite "portable iteration contract":
    # Coverage and native lowering are Milestone 2 acceptance checks. These
    # tests assert provenance and type for each yielded site, not scaffold counts.
    template checkIteration(placement: static ExecutionSpace;
                            granularity: static IterationSpace) =
      let origin = TestLattice[EvenParity]()
      var executed = false
      within placement:
        parallel for site in origin.sites(granularity):
          when granularity == Scalar: check site is ScalarSite[typeof(origin)]
          else: check site is PackedSite[typeof(origin)]
          check site.lattice == origin
          check executionSpace() == placement
          executed = true
      check executed

    test "Host scalar iteration": checkIteration(Host, Scalar)
    test "Host packed iteration": checkIteration(Host, Packed)
    test "Accelerator scalar iteration": checkIteration(Accelerator, Scalar)
    test "Accelerator packed iteration": checkIteration(Accelerator, Packed)

    test "odd-domain iteration retains the selected kind":
      let origin = TestLattice[OddParity]()
      for site in origin.sites(Scalar):
        check site is ScalarSite[TestLattice[OddParity]]
        check site.lattice == origin

    test "iteration space must be static":
      check not compiles(block:
        var granularity = Scalar
        for site in TestLattice[EvenParity]().sites(granularity): discard site)

    test "site iteration requires a Lattice":
      check not compiles(block:
        for site in 5.sites(Scalar): discard site)

    test "parallel requires an Execution Context":
      check not compiles(block:
        parallel for i in 0..<2: discard i)

    test "parallel rejects a non-loop body":
      check not compiles(block:
        within Host:
          parallel: discard)

    test "parallel preserves loop bindings and continue":
      var values: seq[int]
      within Host:
        parallel for i in 0..<5:
          if i mod 2 == 0: continue
          values.add i
      check values == @[1, 3]

    test "parallel propagates exceptions":
      expect IOError:
        within Host:
          parallel for i in 0..<2:
            raise newException(IOError, "loop failed")

    test "nested loops preserve the enclosing context":
      var pairs: seq[(int, int)]
      within Accelerator:
        parallel for i in 0..<2:
          parallel for j in 0..<2:
            check executionSpace() == Accelerator
            pairs.add (i, j)
      check pairs == @[(0, 0), (0, 1), (1, 0), (1, 1)]
