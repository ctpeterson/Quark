# Second oracle establishing Lattice Decompositions and Field Domains

import quark

quark:
  let lattice: Lattice = newLattice([8, 8, 8, 16])

  # A Decomposition belongs to its source Lattice. A Decomposition Domain
  # carries both that Lattice provenance and the Decomposition's semantics.
  let fullDecomposition: Decomposition = lattice.decompose(Full)
  let parityDecomposition: Decomposition = lattice.decompose(EvenOdd)
  let fullDomain: DecompositionDomain = fullDecomposition.domain(Full)
  let evenDomain: DecompositionDomain = parityDecomposition.domain(Even)
  let oddDomain: DecompositionDomain = parityDecomposition.domain(Odd)

  assert fullDomain.volume == lattice.volume
  assert evenDomain.volume == oddDomain.volume
  assert evenDomain.volume + oddDomain.volume == lattice.volume

  # Omitting a Domain selects the Full Decomposition. Domain association is
  # fixed at Field construction so storage can never be reinterpreted later.
  var implicitFullField = lattice.newScalarField(Complex[D])
  var explicitFullField = fullDomain.newScalarField(Complex[D])
  var evenField = evenDomain.newScalarField(Complex[D])
  var oddField = oddDomain.newScalarField(Complex[D])

  within Accelerator:
    implicitFullField := newComplex(1.0, 0.0)
    explicitFullField := implicitFullField
    evenField := newComplex(0.0, 0.0)
    oddField := newComplex(0.0, 0.0)

  # Fields on different Decompositions or different Domains are not directly
  # assignable. Explicit operations may define meaningful Domain transitions.
  doAssert not compiles(
    block:
      within Accelerator:
        evenField := implicitFullField
  )

  doAssert not compiles(
    block:
      within Accelerator:
        evenField := oddField
  )

  within Accelerator:
    var evenView = evenField.view(WriteDiscard)
    var oddView = oddField.view(WriteDiscard)

    parallel for n in evenDomain.sites(Packed):
      evenView[n] := newComplex(0.0, 0.0)

    parallel for n in oddDomain.sites(Packed):
      oddView[n] := newComplex(0.0, 0.0)

  # A Site Index carries Domain provenance as well as Lattice provenance.
  doAssert not compiles(
    block:
      within Accelerator:
        var oddView = oddField.view(WriteDiscard)
        parallel for n in evenDomain.sites(Packed):
          oddView[n] := newComplex(0.0, 0.0)
  )
