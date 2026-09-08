#[
Iteration space

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

import std/[macros]

import lattice

type IterationSpace* = enum
  Scalar = 0, # single-site
  Packed = 1  # SIMD on CPU, coalesced memory access on GPU

type
  ScalarSite* = object
    index*: int
  PackedSite* = object
    index*: int

iterator sites*(lattice: Lattice; space: static IterationSpace): auto =
  discard lattice
  when space == Scalar:
    yield ScalarSite(index: 0)
  else:
    yield PackedSite(index: 0)

macro parallel*(loop: untyped): untyped =
  assert loop.kind == nnkForStmt, "input to parallel macro must be a for loop"

  result = quote do:
    `loop`

when isMainModule:
  import std/[unittest]
  import quark/backend/backend

  suite "smoke tests":
    test "parallel macro with a scalar loop":
      var executed = false
      var lattice = [8, 8, 8, 16].newLattice()
      parallel for i in lattice.sites(Scalar):
        check i is ScalarSite
        executed = true
      check executed

    test "parallel macro with a packed loop":
      var executed = false
      var lattice = [8, 8, 8, 16].newLattice()
      parallel for i in lattice.sites(Packed):
        check i is PackedSite
        executed = true
      check executed
