# First pass oracle establishing basic semantics, spaces, and execution contexts

import quark

quark: # wraps code in appropriate init/finalize
  let lattice: Lattice = newLattice([8, 8, 8, 16])

  # "S" = "single" = 32, "D" = "double" = 64
  var fieldA: Field[Complex[D]] = lattice.newScalarField(Complex[D])
  var fieldB: Field[Complex[D]] = lattice.newScalarField(Complex[D])

  # every placement-sensitive operation belongs to an explicit execution context
  within Accelerator:
    fieldA := newComplex(2.0, 4.0)
    fieldB := 2.0 # implicitly Complex[D](2.0)

  within Accelerator:
    # field views preserve Quark's scoped access and data-preservation semantics
    var fieldAView: FieldView[Complex[D]] = fieldA.view(WriteDiscard)
    var fieldBView: FieldView[Complex[D]] = fieldB.view(Read)

    # a packed site indexes one layout-defined packed group of rank-local sites
    # "parallel" macro executes the loop in parallel on the accelerator
    parallel for n in lattice.sites(Packed):
      fieldAView[n] := 2.0*fieldBView[n] + 1.0

    # field views close at scope exit; later views synchronize data as required

  within Host:
    var fieldAView: FieldView[Complex[D]] = fieldA.view(Read)
    var fieldBView: FieldView[Complex[D]] = fieldB.view(Read)

    # a scalar site indexes one scalar rank-local site
    # "parallel" macro executes the loop in parallel on the host - threaded
    parallel for n in lattice.sites(Scalar):
      assert fieldAView[n].re == 2.0*fieldBView[n].re + 1.0
      assert fieldAView[n].im == 2.0*fieldBView[n].im

    # read field views close at scope exit without modifying their fields

  var fieldsA: seq[Field[Complex[D]]]

  for mu in lattice.directions:
    echo "created fields at mu = ", mu
    fieldsA.add lattice.newScalarField(Complex[D])

    # accelerator loop
    within Accelerator:
      var fieldsAMuView: FieldView[Complex[D]] = fieldsA[mu].view(WriteDiscard)
      var fieldAView: FieldView[Complex[D]] = fieldA.view(Read)
      parallel for n in lattice.sites(Packed):
        fieldsAMuView[n] := fieldAView[n]

    # equally-valid host-side loop
    within Host:
      var fieldsAMuView: FieldView[Complex[D]] = fieldsA[mu].view(ReadWrite)
      var fieldAView: FieldView[Complex[D]] = fieldA.view(Read)
      parallel for n in lattice.sites(Packed):
        fieldsAMuView[n] += fieldAView[n]
