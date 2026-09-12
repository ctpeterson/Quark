# Integrated oracle for scalar-valued Fields, site arithmetic, and scoped execution.
# Run this same source with each adapter. Native acceptance belongs to Milestone 2.

import quark

quark: # wraps code in the selected backend's initialization/finalization
  let lattice: Lattice = [8, 8, 8, 16].newLattice()
  # Explicit construction is also part of the portable interface:
  # let lattice: Lattice = [8, 8, 8, 16].newLattice(
  #   rankPartition = [1, 1, 2, 2], # split the global lattice among four MPI ranks
  #   packedPartition = [2, 2, 1, 1] # further partition each rank-local lattice
  # )
  # Exercise that configuration in a separate layout oracle with matching launch
  # and packing requirements; the default program must not require four ranks.

  # This helper only verifies results. Every numerical kernel below keeps its
  # Execution Context, iteration space, and access modes visible at the call site.
  # Expected components are independently calculated constants, not Quark algebra.
  # An absolute tolerance suffices for these bounded double-precision examples;
  # no bitwise agreement between different backend evaluation orders is required.
  template checkFieldValue(field: untyped; expectedRe, expectedIm: float64) =
    within Host:
      let checkedView = field.view(Read)
      parallel for n in lattice.sites(Scalar):
        doAssert abs(checkedView[n].re - expectedRe) <= 1.0e-12
        doAssert abs(checkedView[n].im - expectedIm) <= 1.0e-12

  # "S" means single precision (32 bits); "D" means double (64 bits).
  var fieldA: Field[Complex[D]] = lattice.newField(Complex[D])
  var fieldB: Field[Complex[D]] = lattice.newField(Complex[D])
  var fieldC: Field[Complex[D]] = lattice.newField(Complex[D])

  within Accelerator:
    fieldA := newComplex(2.0, 4.0)
    fieldB := 2.0 # broadcast a real literal as a Complex[D] value
  checkFieldValue(fieldA, 2.0, 4.0)
  checkFieldValue(fieldB, 2.0, 0.0)

  within Accelerator:
    var fieldAView = fieldA.view(WriteDiscard)
    var fieldBView = fieldB.view(Read)
    # Each Packed Site accesses a layout-defined group of rank-local sites.
    parallel for n in lattice.sites(Packed):
      fieldAView[n] := 2.0*fieldBView[n] + 1.0
    # WriteDiscard never reads old A values and covers the complete viewed region.

  within Host:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    # Reopening on Host makes completed accelerator writes visible.
    parallel for n in lattice.sites(Scalar):
      assert fieldAView[n].re == 2.0*fieldBView[n].re + 1.0
      assert fieldAView[n].im == 2.0*fieldBView[n].im
  checkFieldValue(fieldA, 5.0, 0.0)

  var fieldsA: seq[Field[Complex[D]]]
  for mu in lattice.directions:
    echo "created fields at mu = ", mu
    fieldsA.add lattice.newField(Complex[D])

    within Accelerator:
      var fieldsAMuView = fieldsA[mu].view(WriteDiscard)
      var fieldAView = fieldA.view(Read)
      parallel for n in lattice.sites(Packed):
        fieldsAMuView[n] := fieldAView[n]
    checkFieldValue(fieldsA[mu], 5.0, 0.0)

    within Host:
      var fieldsAMuView = fieldsA[mu].view(ReadWrite)
      var fieldAView = fieldA.view(Read)
      parallel for n in lattice.sites(Packed):
        fieldsAMuView[n] += fieldAView[n]
    checkFieldValue(fieldsA[mu], 10.0, 0.0)

    within Accelerator:
      var fieldsAMuView = fieldsA[mu].view(ReadWrite)
      parallel for n in lattice.sites(Packed):
        fieldsAMuView[n] += 1.0
    checkFieldValue(fieldsA[mu], 11.0, 0.0)

    within Accelerator:
      var fieldsAMuView = fieldsA[mu].view(ReadWrite)
      let number: Complex[D] = newComplex(1.0, 0.0)
      parallel for n in lattice.sites(Packed):
        fieldsAMuView[n] += number
    checkFieldValue(fieldsA[mu], 12.0, 0.0)

  doAssert fieldsA.len == lattice.dimensions
  checkFieldValue(fieldA, 5.0, 0.0) # copying sites did not alias the source storage

  # Genuinely complex, distinct inputs expose real/imaginary cross terms and
  # operand order. Every divisor used below is nonzero, including B - 2.0.
  within Accelerator:
    fieldA := newComplex(2.0, 4.0)
    fieldB := newComplex(3.0, -2.0)
  let number: Complex[D] = newComplex(1.0, 1.0)

  # These are indexed, pointwise site expressions. Whole-Field expression syntax
  # and reductions have their own future oracles. For numeric sites, / is Real
  # or Complex division; Integer sites use div and mod instead.

  # Mixed addition.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := number*fieldAView[n] + 2.0*fieldBView[n] + number + 2.0
  checkFieldValue(fieldC, 7.0, 3.0)

  # Mixed subtraction.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := number*fieldAView[n] - 2.0*fieldBView[n] - number - 2.0
  checkFieldValue(fieldC, -11.0, 9.0)

  # Pointwise complex multiplication.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := fieldAView[n] * fieldBView[n]
  checkFieldValue(fieldC, 14.0, 8.0)

  # Chained pointwise complex division.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := fieldAView[n] / fieldBView[n] / number / 2.0
  checkFieldValue(fieldC, 7.0/26.0, 9.0/26.0)

  # Quotient of sums.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := (fieldAView[n] + number) / (fieldBView[n] + 2.0)
  checkFieldValue(fieldC, 5.0/29.0, 31.0/29.0)

  # Quotient of differences.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := (fieldAView[n] - number) / (fieldBView[n] - 2.0)
  checkFieldValue(fieldC, -1.0, 1.0)

  # Quotient of affine expressions.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := (fieldAView[n] * number + 1.0) / (fieldBView[n] * 2.0 + number)
  checkFieldValue(fieldC, -25.0/58.0, 39.0/58.0)

  # Quotient with subtracted offsets.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := (fieldAView[n] * number - 1.0) / (fieldBView[n] * 2.0 - number)
  checkFieldValue(fieldC, -9.0/10.0, 3.0/10.0)

  # Reversed scaling and addition operands.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := 2.0 + fieldAView[n]*number + fieldBView[n]*2.0 + number
  checkFieldValue(fieldC, 7.0, 3.0)

  # Literal minus site.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := 2.0 - fieldAView[n]
  checkFieldValue(fieldC, 0.0, -4.0)

  # Complex scalar minus site.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := number - fieldAView[n]
  checkFieldValue(fieldC, -1.0, -3.0)

  # Literal divided by site.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := 2.0 / fieldAView[n]
  checkFieldValue(fieldC, 1.0/5.0, -2.0/5.0)

  # Complex scalar divided by site.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := number / fieldAView[n]
  checkFieldValue(fieldC, 3.0/10.0, -1.0/10.0)

  # Unary signs.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := -fieldAView[n] + +fieldBView[n]
  checkFieldValue(fieldC, 1.0, -6.0)

  # Multiplication precedence.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := fieldAView[n] + fieldBView[n] * number
  checkFieldValue(fieldC, 7.0, 5.0)

  # Parenthesized addition.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := (fieldAView[n] + fieldBView[n]) * number
  checkFieldValue(fieldC, 3.0, 7.0)

  # Left-associated division.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := (fieldAView[n] / fieldBView[n]) / number
  checkFieldValue(fieldC, 7.0/13.0, 9.0/13.0)

  # Parenthesized divisor.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := fieldAView[n] / (fieldBView[n] / number)
  checkFieldValue(fieldC, -18.0/13.0, 14.0/13.0)

  # Compound updates read and write the destination; every step is observed.
  within Accelerator:
    var fieldAView = fieldA.view(Read)
    var fieldCView = fieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] := fieldAView[n]
  checkFieldValue(fieldC, 2.0, 4.0)

  within Accelerator:
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(ReadWrite)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] += fieldBView[n]
  checkFieldValue(fieldC, 5.0, 2.0)

  within Accelerator:
    var fieldCView = fieldC.view(ReadWrite)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] -= number
  checkFieldValue(fieldC, 4.0, 1.0)

  within Accelerator:
    var fieldCView = fieldC.view(ReadWrite)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] *= 2.0
  checkFieldValue(fieldC, 8.0, 2.0)

  within Accelerator:
    var fieldBView = fieldB.view(Read)
    var fieldCView = fieldC.view(ReadWrite)
    parallel for n in lattice.sites(Packed):
      fieldCView[n] /= fieldBView[n]
  checkFieldValue(fieldC, 20.0/13.0, 22.0/13.0)

  # Arithmetic and updates must leave their input Fields and independent
  # sequence entries unchanged.
  checkFieldValue(fieldA, 2.0, 4.0)
  checkFieldValue(fieldB, 3.0, -2.0)
  for mu in lattice.directions:
    checkFieldValue(fieldsA[mu], 12.0, 0.0)

  # Positive update cases above must not broaden access through other modes.
  doAssert not compiles(block:
    within Host:
      var readView = fieldC.view(Read)
      parallel for n in lattice.sites(Scalar):
        readView[n] += 1.0)
  doAssert not compiles(block:
    within Host:
      var discardView = fieldC.view(WriteDiscard)
      parallel for n in lattice.sites(Scalar):
        discardView[n] += 1.0)
  doAssert not compiles(block:
    within Host:
      var discardView = fieldC.view(WriteDiscard)
      parallel for n in lattice.sites(Scalar):
        discard discardView[n].re)


  # Mixed numeric families: Kind and Precision follow the operands, including
  # the intermediate expression, before assignment to the destination Field.
  let integersS = lattice.newField(Integer[S])
  let integersD = lattice.newField(Integer[D])
  let realsS = lattice.newField(Real[S])
  let realsD = lattice.newField(Real[D])
  let complexesS = lattice.newField(Complex[S])
  let complexesD = lattice.newField(Complex[D])
  let integerResult = lattice.newField(Integer[D])
  let realResult = lattice.newField(Real[D])
  let complexResult = lattice.newField(Complex[D])
  within Host:
    integersS := newInteger(3'i32)
    integersD := newInteger(7'i64)
    realsS := newReal(1.5'f32)
    realsD := newReal(2.25)
    complexesS := newComplex(2.0'f32, -1.0'f32)
    complexesD := newComplex(-1.0, 3.0)

  template checkRealField(field: untyped; expected: float64) =
    within Host:
      let observed = field.view(Read)
      for n in lattice.sites(Scalar):
        doAssert abs(observed[n] - expected) <= 1.0e-12

  template checkIntegerField(field: untyped; expected: int64) =
    within Host:
      let observed = field.view(Read)
      for n in lattice.sites(Scalar):
        doAssert observed[n] == expected

  # integer precision promotion.
  within Accelerator:
    let a = integersS.view(Read)
    let b = integersD.view(Read)
    var output = integerResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] + b[n]) is IntegerNumber[D]
      output[n] := a[n] + b[n]
  checkIntegerField(integerResult, 10'i64)

  # integer subtraction in reverse precision order.
  within Accelerator:
    let a = integersD.view(Read)
    let b = integersS.view(Read)
    var output = integerResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] - b[n]) is IntegerNumber[D]
      output[n] := a[n] - b[n]
  checkIntegerField(integerResult, 4'i64)

  # integer division.
  within Accelerator:
    let a = integersD.view(Read)
    let b = integersS.view(Read)
    var output = integerResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] div b[n]) is IntegerNumber[D]
      output[n] := a[n] div b[n]
  checkIntegerField(integerResult, 2'i64)

  # integer remainder.
  within Accelerator:
    let a = integersD.view(Read)
    let b = integersS.view(Read)
    var output = integerResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] mod b[n]) is IntegerNumber[D]
      output[n] := a[n] mod b[n]
  checkIntegerField(integerResult, 1'i64)

  # real precision promotion.
  within Accelerator:
    let a = realsS.view(Read)
    let b = realsD.view(Read)
    var output = realResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] + b[n]) is RealNumber[D]
      output[n] := a[n] + b[n]
  checkRealField(realResult, 3.75)

  # real division in reverse precision order.
  within Accelerator:
    let a = realsD.view(Read)
    let b = realsS.view(Read)
    var output = realResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] / b[n]) is RealNumber[D]
      output[n] := a[n] / b[n]
  checkRealField(realResult, 1.5)

  # complex precision promotion.
  within Accelerator:
    let a = complexesS.view(Read)
    let b = complexesD.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] + b[n]) is ComplexNumber[D]
      output[n] := a[n] + b[n]
  checkFieldValue(complexResult, 1.0, 2.0)

  # complex product in reverse precision order.
  within Accelerator:
    let a = complexesD.view(Read)
    let b = complexesS.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] * b[n]) is ComplexNumber[D]
      output[n] := a[n] * b[n]
  checkFieldValue(complexResult, 1.0, 7.0)

  # Integer plus Real.
  within Accelerator:
    let a = integersS.view(Read)
    let b = realsD.view(Read)
    var output = realResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] + b[n]) is RealNumber[D]
      output[n] := a[n] + b[n]
  checkRealField(realResult, 5.25)

  # Real minus Integer.
  within Accelerator:
    let a = realsS.view(Read)
    let b = integersD.view(Read)
    var output = realResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] - b[n]) is RealNumber[D]
      output[n] := a[n] - b[n]
  checkRealField(realResult, -5.5)

  # Integer times Real.
  within Accelerator:
    let a = integersD.view(Read)
    let b = realsS.view(Read)
    var output = realResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] * b[n]) is RealNumber[D]
      output[n] := a[n] * b[n]
  checkRealField(realResult, 10.5)

  # Real divided by Integer.
  within Accelerator:
    let a = realsD.view(Read)
    let b = integersS.view(Read)
    var output = realResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] / b[n]) is RealNumber[D]
      output[n] := a[n] / b[n]
  checkRealField(realResult, 0.75)

  # Integer plus Complex.
  within Accelerator:
    let a = integersD.view(Read)
    let b = complexesS.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] + b[n]) is ComplexNumber[D]
      output[n] := a[n] + b[n]
  checkFieldValue(complexResult, 9.0, -1.0)

  # Complex minus Integer.
  within Accelerator:
    let a = complexesD.view(Read)
    let b = integersS.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] - b[n]) is ComplexNumber[D]
      output[n] := a[n] - b[n]
  checkFieldValue(complexResult, -4.0, 3.0)

  # Integer times Complex.
  within Accelerator:
    let a = integersS.view(Read)
    let b = complexesD.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] * b[n]) is ComplexNumber[D]
      output[n] := a[n] * b[n]
  checkFieldValue(complexResult, -3.0, 9.0)

  # Complex divided by Integer.
  within Accelerator:
    let a = complexesS.view(Read)
    let b = integersD.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] / b[n]) is ComplexNumber[D]
      output[n] := a[n] / b[n]
  checkFieldValue(complexResult, 2.0/7.0, -1.0/7.0)

  # Real plus Complex.
  within Accelerator:
    let a = realsD.view(Read)
    let b = complexesS.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] + b[n]) is ComplexNumber[D]
      output[n] := a[n] + b[n]
  checkFieldValue(complexResult, 4.25, -1.0)

  # Complex minus Real.
  within Accelerator:
    let a = complexesD.view(Read)
    let b = realsS.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] - b[n]) is ComplexNumber[D]
      output[n] := a[n] - b[n]
  checkFieldValue(complexResult, -2.5, 3.0)

  # Real times Complex.
  within Accelerator:
    let a = realsS.view(Read)
    let b = complexesD.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] * b[n]) is ComplexNumber[D]
      output[n] := a[n] * b[n]
  checkFieldValue(complexResult, -1.5, 4.5)

  # Complex divided by Real.
  within Accelerator:
    let a = complexesS.view(Read)
    let b = realsD.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(a[n] / b[n]) is ComplexNumber[D]
      output[n] := a[n] / b[n]
  checkFieldValue(complexResult, 8.0/9.0, -4.0/9.0)

  # Chain all three numeric Kinds; the Integer/Real intermediate is Real[S].
  within Accelerator:
    let i = integersS.view(Read)
    let r = realsS.view(Read)
    let z = complexesD.view(Read)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static:
        doAssert typeof(i[n] + r[n]) is RealNumber[S]
        doAssert typeof((i[n] + r[n]) * z[n]) is ComplexNumber[D]
      output[n] := (i[n] + r[n]) * z[n]
  checkFieldValue(complexResult, -4.5, 13.5)

  # Concrete portable numeric values also mix with site expressions.
  within Accelerator:
    let z = complexesS.view(Read)
    let r = newReal(2.0)
    let i = newInteger(3'i32)
    var output = complexResult.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(r*z[n] + i) is ComplexNumber[D]
      output[n] := r*z[n] + i
  checkFieldValue(complexResult, 7.0, -2.0)

  doAssert not compiles(block:
    within Host:
      let i = integersD.view(Read)
      for n in lattice.sites(Scalar): discard i[n] / i[n])
  doAssert not compiles(block:
    within Host:
      let r = realsD.view(Read)
      for n in lattice.sites(Scalar): discard r[n] div r[n])

  # Seed distinguishable rank-local values in the ordinary Scalar traversal.
  # The serial counters belong to this test, never to a parallel kernel. No
  # assumption is made about coordinates, rank numbering, or packing lanes.
  let pattern = lattice.newField(Complex[D])
  let transformed = lattice.newField(Complex[D])
  within Host:
    var output = pattern.view(WriteDiscard)
    var ordinal = 0
    for n in lattice.sites(Scalar):
      output[n] := newComplex(float64(ordinal mod 17 + 1), float64(ordinal mod 5 - 2))
      inc ordinal
    doAssert ordinal == lattice.rankGeometry.volume

  within Accelerator:
    let input = pattern.view(Read)
    var output = transformed.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      output[n] := 2.0*input[n] + newComplex(3.0, -1.0)

  within Host:
    let observed = transformed.view(Read)
    var ordinal = 0
    for n in lattice.sites(Scalar):
      doAssert abs(observed[n].re - float64(2*(ordinal mod 17 + 1) + 3)) <= 1.0e-12
      doAssert abs(observed[n].im - float64(2*(ordinal mod 5 - 2) - 1)) <= 1.0e-12
      inc ordinal
    doAssert ordinal == lattice.rankGeometry.volume

  # Modify only part of a ReadWrite view. Untouched values must survive.
  within Host:
    var output = transformed.view(ReadWrite)
    var ordinal = 0
    for n in lattice.sites(Scalar):
      if ordinal mod 2 == 0: output[n] += 1.0
      inc ordinal
  within Accelerator:
    var output = transformed.view(ReadWrite)
    parallel for n in lattice.sites(Scalar):
      output[n] *= 2.0
  within Host:
    let observed = transformed.view(Read)
    var ordinal = 0
    for n in lattice.sites(Scalar):
      let increment = if ordinal mod 2 == 0: 1 else: 0
      doAssert abs(observed[n].re - float64(2*(2*(ordinal mod 17 + 1) + 3 + increment))) <= 1.0e-12
      doAssert abs(observed[n].im - float64(2*(2*(ordinal mod 5 - 2) - 1))) <= 1.0e-12
      inc ordinal
    doAssert ordinal == lattice.rankGeometry.volume

  # Ordinary Field handle copies alias; := copies values into independent storage.
  let source = lattice.newField(Complex[D])
  let destination = lattice.newField(Complex[D])
  let alias = source
  within Host:
    source := newComplex(2.0, 3.0)
    destination := newComplex(7.0, -1.0)
    var update = alias.view(ReadWrite)
    parallel for n in lattice.sites(Scalar): update[n] += 1.0
  checkFieldValue(source, 3.0, 3.0)
  checkFieldValue(destination, 7.0, -1.0)
  within Accelerator:
    destination := source
  within Host:
    alias := newComplex(10.0, 2.0)
  checkFieldValue(source, 10.0, 2.0)
  checkFieldValue(destination, 3.0, 3.0)

  # A self-referential site update reads the previous value before assignment.
  within Accelerator:
    var update = destination.view(ReadWrite)
    parallel for n in lattice.sites(Packed): update[n] := 2.0*update[n] + 1.0
  checkFieldValue(destination, 7.0, 6.0)

  # Early exits close actual Views before the caller reopens the Field.
  proc updateAndReturn(field: Field[Complex[D]]) =
    within Host:
      var update = field.view(ReadWrite)
      parallel for n in field.lattice.sites(Scalar): update[n] += 1.0
      return
  updateAndReturn(destination)
  checkFieldValue(destination, 8.0, 6.0)

  proc updateAndRaise(field: Field[Complex[D]]) =
    within Host:
      var update = field.view(ReadWrite)
      parallel for n in field.lattice.sites(Scalar): update[n] += 1.0
      raise newException(IOError, "oracle scope exit")
  var caught = false
  try: updateAndRaise(destination)
  except IOError: caught = true
  doAssert caught
  checkFieldValue(destination, 9.0, 6.0)

  # An inner scope has a separate lifetime, even for the same placement.
  within Host:
    let outer = source.view(Read)
    within Host:
      let inner = destination.view(Read)
      for n in lattice.sites(Scalar): doAssert abs(inner[n].re - 9.0) <= 1.0e-12
    for n in lattice.sites(Scalar): doAssert abs(outer[n].re - 10.0) <= 1.0e-12
