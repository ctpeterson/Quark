# Second oracle establishing Lattice Decompositions and Field Domains

import quark

quark:
  let lattice: Lattice = [8, 8, 8, 16].newLattice() # default is Full

  # The backend supplies each selected Lattice and its native site organization.
  let even: Lattice = lattice.newSublattice(EvenParity)
  let odd: Lattice = lattice.newSublattice(OddParity)

  assert even.volume == odd.volume
  assert even.volume + odd.volume == lattice.volume

  var fullField = lattice.newField(Complex[D])
  var evenField = even.newField(Complex[D])
  var oddField = odd.newField(Complex[D])

  within Accelerator:
    fullField := newComplex(1.0, 0.0)
    evenField := newComplex(0.0, 0.0)
    oddField := newComplex(0.0, 0.0)

  # Fields on different Domains are not compatible. Explicit operations may define
  # meaningful Domain transitions.
  doAssert not compiles(
    block:
      within Accelerator:
        evenField := fullField
  )

  doAssert not compiles(
    block:
      within Accelerator:
        evenField := oddField
  )

  within Accelerator:
    var evenView = evenField.view(WriteDiscard)
    var oddView = oddField.view(WriteDiscard)

    parallel for n in even.sites(Packed):
      evenView[n] := newComplex(0.0, 0.0)

    parallel for n in odd.sites(Packed):
      oddView[n] := newComplex(0.0, 0.0)

  # A Site Index carries Domain provenance as well as Lattice provenance.
  doAssert not compiles(
    block:
      within Accelerator:
        var oddView = oddField.view(WriteDiscard)
        parallel for n in even.sites(Packed):
          oddView[n] := newComplex(0.0, 0.0)
  )

  # Selecting Full or repeating a parity selection preserves conformability.
  let fullAgain = lattice.newSublattice(Full)
  let evenAgain = lattice.newSublattice(EvenParity)
  let oddAgain = lattice.newSublattice(OddParity)
  doAssert conformable(lattice, fullAgain)
  doAssert conformable(even, evenAgain)
  doAssert conformable(odd, oddAgain)
  doAssert not conformable(even, odd)
  doAssert not conformable(even, lattice)
  doAssert even.domain == EvenParity
  doAssert odd.domain == OddParity
  doAssert even.decomposition == SiteParity
  doAssert fullAgain.decomposition == NoDecomposition

  # Observe the adapter's iterators, without reimplementing partition validation.
  var fullCount, evenCount, oddCount: int
  for n in lattice.sites(Scalar):
    doAssert conformable(n.lattice, lattice)
    inc fullCount
  for n in even.sites(Scalar):
    doAssert conformable(n.lattice, even)
    inc evenCount
  for n in odd.sites(Scalar):
    doAssert conformable(n.lattice, odd)
    inc oddCount
  doAssert fullCount == lattice.rankGeometry.volume
  doAssert evenCount + oddCount == fullCount

  template checkSelected(field, selected: untyped; expectedRe, expectedIm: float64) =
    within Host:
      let observed = field.view(Read)
      var count = 0
      for n in selected.sites(Scalar):
        doAssert abs(observed[n].re - expectedRe) <= 1.0e-12
        doAssert abs(observed[n].im - expectedIm) <= 1.0e-12
        inc count
      when selected.domain == EvenParity: doAssert count == evenCount
      elif selected.domain == OddParity: doAssert count == oddCount
      else: doAssert count == fullCount

  checkSelected(fullField, lattice, 1.0, 0.0)
  checkSelected(evenField, even, 0.0, 0.0)
  checkSelected(oddField, odd, 0.0, 0.0)

  # Separately allocated Fields on these Lattices have independent storage.
  within Accelerator:
    var ev = evenField.view(WriteDiscard)
    var ov = oddField.view(WriteDiscard)
    parallel for n in even.sites(Packed): ev[n] := newComplex(2.0, 1.0)
    parallel for n in odd.sites(Packed): ov[n] := newComplex(-3.0, 4.0)
  checkSelected(evenField, evenAgain, 2.0, 1.0)
  checkSelected(oddField, oddAgain, -3.0, 4.0)
  checkSelected(fullField, fullAgain, 1.0, 0.0)

  # Same-kind provenance from an equivalent selection is valid for assignment
  # and indexing. These positives accompany the cross-kind rejection examples.
  let evenCopy = evenAgain.newField(Complex[D])
  within Accelerator:
    evenCopy := evenField
  checkSelected(evenCopy, even, 2.0, 1.0)
  within Host:
    var ev = evenField.view(ReadWrite)
    parallel for n in evenAgain.sites(Scalar): ev[n] += newComplex(1.0, -1.0)
  checkSelected(evenField, even, 3.0, 0.0)
  checkSelected(evenCopy, evenAgain, 2.0, 1.0)
  checkSelected(oddField, odd, -3.0, 4.0)
  checkSelected(fullField, lattice, 1.0, 0.0)

  # Nonuniform data survive Packed arithmetic on the parity iteration space.
  within Host:
    var ev = evenCopy.view(WriteDiscard)
    var ordinal = 0
    for n in even.sites(Scalar):
      ev[n] := newComplex(float64(ordinal mod 11), float64(ordinal mod 7))
      inc ordinal
    doAssert ordinal == evenCount
  within Accelerator:
    var ev = evenCopy.view(ReadWrite)
    parallel for n in evenAgain.sites(Packed): ev[n] := 2.0*ev[n] + 1.0
  within Host:
    let ev = evenCopy.view(Read)
    var ordinal = 0
    for n in even.sites(Scalar):
      doAssert abs(ev[n].re - float64(2*(ordinal mod 11) + 1)) <= 1.0e-12
      doAssert abs(ev[n].im - float64(2*(ordinal mod 7))) <= 1.0e-12
      inc ordinal
    doAssert ordinal == evenCount

  doAssert not compiles(block:
    within Host: fullField := evenField)
  doAssert not compiles(block:
    within Host: oddField := evenField)
  doAssert not compiles(block:
    within Host:
      var ev = evenField.view(WriteDiscard)
      for n in lattice.sites(Scalar): ev[n] := 0.0)
  doAssert not compiles(block:
    within Host:
      var full = fullField.view(WriteDiscard)
      for n in odd.sites(Scalar): full[n] := 0.0)
  doAssert not compiles(block:
    within Host:
      var ev = evenField.view(WriteDiscard)
      let ov = oddField.view(Read)
      for n in even.sites(Scalar): ev[n] := ov[n] + 1.0)

  # Equal extents and equal Domain kinds do not confer instance provenance.
  # Validation is delegated through the adapter; no layout comparison is copied
  # into this program. The exact diagnostic wording is not part of the oracle.
  let unrelated = [8, 8, 8, 16].newLattice()
  let unrelatedEven = unrelated.newSublattice(EvenParity)
  doAssert not conformable(even, unrelatedEven)
  let unrelatedField = unrelatedEven.newField(Complex[D])
  within Host:
    unrelatedField := 0.0
  var rejected = false
  try:
    within Host:
      let wrong = unrelatedField.view(Read)
      for n in even.sites(Scalar): discard wrong[n].re
  except ValueError: rejected = true
  doAssert rejected

  rejected = false
  try:
    within Host: unrelatedField := evenField
  except ValueError: rejected = true
  doAssert rejected
  checkSelected(evenField, even, 3.0, 0.0)
