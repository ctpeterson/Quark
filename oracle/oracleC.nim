# Third oracle establishing tensor-valued fields and semantics

import quark

quark:
  let lattice: Lattice = [8, 8, 8, 16].newLattice()

  var scalarFieldA: Field[Complex[D]] = lattice.newField(Complex[D])
  var scalarFieldB: Field[Complex[D]] = lattice.newField(Complex[D])
  var scalarFieldC: Field[Complex[D]] = lattice.newField(Complex[D])

  var vectorFieldA: Field[Vector[Complex[D], 3]] = lattice.newField(Vector[Complex[D], 3])
  var vectorFieldB: Field[Vector[Complex[D], 3]] = lattice.newField(Vector[Complex[D], 3])
  var vectorFieldC: Field[Vector[Complex[D], 3]] = lattice.newField(Vector[Complex[D], 3])

  var matrixFieldA: Field[Matrix[Complex[D], 3]] = lattice.newField(Matrix[Complex[D], 3])
  var matrixFieldB: Field[Matrix[Complex[D], 3]] = lattice.newField(Matrix[Complex[D], 3])
  var matrixFieldC: Field[Matrix[Complex[D], 3]] = lattice.newField(Matrix[Complex[D], 3])

  var spinVectorFieldA: Field[Spin[Vector[Complex[D], 3]]] = lattice.newField(Spin[Vector[Complex[D], 3]])
  var spinVectorFieldB: Field[Spin[Vector[Complex[D], 3]]] = lattice.newField(Spin[Vector[Complex[D], 3]])
  var spinVectorFieldC: Field[Spin[Vector[Complex[D], 3]]] = lattice.newField(Spin[Vector[Complex[D], 3]])

  var spinMatrixFieldA: Field[Spin[Matrix[Complex[D], 3]]] = lattice.newField(Spin[Matrix[Complex[D], 3]])
  var spinMatrixFieldB: Field[Spin[Matrix[Complex[D], 3]]] = lattice.newField(Spin[Matrix[Complex[D], 3]])
  var spinMatrixFieldC: Field[Spin[Matrix[Complex[D], 3]]] = lattice.newField(Spin[Matrix[Complex[D], 3]])

  # Shape is independent of Site Granularity. Tensor indices choose components,
  # never packing lanes. Every WriteDiscard kernel assigns every leaf.
  static:
    doAssert Vector[Complex[D], 3] is VectorObject[Complex[D], 3]
    doAssert Matrix[Complex[D], 3] is MatrixObject[Complex[D], 3]
    doAssert Spin[Vector[Complex[D], 3]] is SpinObject[Vector[Complex[D], 3]]
    doAssert Spin[Matrix[Complex[D], 3]] is SpinObject[Matrix[Complex[D], 3]]

  template closeTo(value: untyped; expectedRe, expectedIm: float64) =
    doAssert abs(value.re - expectedRe) <= 1.0e-12
    doAssert abs(value.im - expectedIm) <= 1.0e-12

  template checkVector(field: untyped; expectedRe, expectedIm: array[3, float64]) =
    within Host:
      let observed = field.view(Read)
      for n in lattice.sites(Scalar):
        for j in 0..<3: closeTo(observed[n][j], expectedRe[j], expectedIm[j])

  template checkMatrix(field: untyped;
                       expectedRe, expectedIm: array[3, array[3, float64]]) =
    within Host:
      let observed = field.view(Read)
      for n in lattice.sites(Scalar):
        for i in 0..<3:
          for j in 0..<3: closeTo(observed[n][i, j], expectedRe[i][j], expectedIm[i][j])

  within Accelerator:
    scalarFieldA := newComplex(2.0, 1.0)
    scalarFieldB := newComplex(1.0, -1.0)
    let a = scalarFieldA.view(Read)
    let b = scalarFieldB.view(Read)
    var c = scalarFieldC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed): c[n] := (a[n] + b[n]) / (a[n] - b[n])
  within Host:
    let c = scalarFieldC.view(Read)
    for n in lattice.sites(Scalar): closeTo(c[n], 3.0/5.0, -6.0/5.0)
  const vARe = [1.0, 2.0, -1.0]
  const vAIm = [1.0, -1.0, 2.0]
  const vBRe = [2.0, -1.0, 3.0]
  const vBIm = [0.0, 1.0, -1.0]
  const mARe = [[1.0, 2.0, 0.0], [0.0, 1.0, 1.0], [2.0, 0.0, 1.0]]
  const mAIm = [[1.0, 0.0, 0.0], [0.0, -1.0, 0.0], [0.0, 0.0, 0.0]]
  const mBRe = [[0.0, 1.0, 1.0], [1.0, 2.0, 0.0], [0.0, 1.0, 1.0]]
  const mBIm = [[0.0, 0.0, -1.0], [0.0, 0.0, 0.0], [0.0, 1.0, 0.0]]

  # The same source exercises ordinary and spin-tagged vector algebra.
  template exerciseVectors(aField, bField, cField: untyped) =
    within Accelerator:
      var a = aField.view(WriteDiscard)
      var b = bField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        for j in 0..<3:
          a[n][j] := newComplex(vARe[j], vAIm[j])
          b[n][j] := newComplex(vBRe[j], vBIm[j])
    checkVector(aField, vARe, vAIm)
    checkVector(bField, vBRe, vBIm)

    # Vector sum.
    within Accelerator:
      let a = aField.view(Read)
      let b = bField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(a[n] + b[n]) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(a[n] + b[n]) is SpinObject[T]
        c[n] := a[n] + b[n]
    checkVector(cField, [3.0, 1.0, 2.0], [1.0, 0.0, 1.0])

    # Vector difference.
    within Accelerator:
      let a = aField.view(Read)
      let b = bField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(a[n] - b[n]) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(a[n] - b[n]) is SpinObject[T]
        c[n] := a[n] - b[n]
    checkVector(cField, [-1.0, 3.0, -4.0], [1.0, -2.0, 3.0])

    # Vector unary plus.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(+a[n]) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(+a[n]) is SpinObject[T]
        c[n] := +a[n]
    checkVector(cField, [1.0, 2.0, -1.0], [1.0, -1.0, 2.0])

    # Vector unary minus.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(-a[n]) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(-a[n]) is SpinObject[T]
        c[n] := -a[n]
    checkVector(cField, [-1.0, -2.0, 1.0], [-1.0, 1.0, -2.0])

    # Vector literal scaling.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(2.0*a[n]) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(2.0*a[n]) is SpinObject[T]
        c[n] := 2.0*a[n]
    checkVector(cField, [2.0, 4.0, -2.0], [2.0, -2.0, 4.0])

    # Vector right complex scaling.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(a[n]*newComplex(2.0, 1.0)) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(a[n]*newComplex(2.0, 1.0)) is SpinObject[T]
        c[n] := a[n]*newComplex(2.0, 1.0)
    checkVector(cField, [1.0, 5.0, -4.0], [3.0, 0.0, 3.0])

    # Vector left complex scaling.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(newComplex(2.0, 1.0)*a[n]) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(newComplex(2.0, 1.0)*a[n]) is SpinObject[T]
        c[n] := newComplex(2.0, 1.0)*a[n]
    checkVector(cField, [1.0, 5.0, -4.0], [3.0, 0.0, 3.0])

    # Vector numeric Field coefficient.
    within Accelerator:
      let a = aField.view(Read)
      let b = bField.view(Read)
      let scale = scalarFieldA.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(scale[n]*a[n] + b[n]) is VectorObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(scale[n]*a[n] + b[n]) is SpinObject[T]
        c[n] := scale[n]*a[n] + b[n]
    checkVector(cField, [3.0, 4.0, -1.0], [3.0, 1.0, 2.0])

    # Only one component changes; ReadWrite preserves the other components.
    within Host:
      var c = cField.view(ReadWrite)
      parallel for n in lattice.sites(Scalar): c[n][1] += newComplex(1.0, -2.0)
    checkVector(cField, [3.0, 5.0, -1.0], [3.0, -1.0, 2.0])
    checkVector(aField, vARe, vAIm)
    checkVector(bField, vBRe, vBIm)

  exerciseVectors(vectorFieldA, vectorFieldB, vectorFieldC)
  exerciseVectors(spinVectorFieldA, spinVectorFieldB, spinVectorFieldC)

  template exerciseMatrices(aField, bField, cField, xField, yField: untyped) =
    within Accelerator:
      var a = aField.view(WriteDiscard)
      var b = bField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        for i in 0..<3:
          for j in 0..<3:
            a[n][i, j] := newComplex(mARe[i][j], mAIm[i][j])
            b[n][i, j] := newComplex(mBRe[i][j], mBIm[i][j])
    checkMatrix(aField, mARe, mAIm)
    checkMatrix(bField, mBRe, mBIm)

    # Matrix sum; products contract indices, not entries independently.
    within Accelerator:
      let a = aField.view(Read)
      let b = bField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(a[n] + b[n]) is MatrixObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(a[n] + b[n]) is SpinObject[T]
        c[n] := a[n] + b[n]
    checkMatrix(cField, [[1.0, 3.0, 1.0], [1.0, 3.0, 1.0], [2.0, 1.0, 2.0]], [[1.0, 0.0, -1.0], [0.0, -1.0, 0.0], [0.0, 1.0, 0.0]])

    # Matrix difference; products contract indices, not entries independently.
    within Accelerator:
      let a = aField.view(Read)
      let b = bField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(a[n] - b[n]) is MatrixObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(a[n] - b[n]) is SpinObject[T]
        c[n] := a[n] - b[n]
    checkMatrix(cField, [[1.0, 1.0, -1.0], [-1.0, -1.0, 1.0], [2.0, -1.0, 0.0]], [[1.0, 0.0, 1.0], [0.0, -1.0, 0.0], [0.0, -1.0, 0.0]])

    # Matrix unary minus; products contract indices, not entries independently.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(-a[n]) is MatrixObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(-a[n]) is SpinObject[T]
        c[n] := -a[n]
    checkMatrix(cField, [[-1.0, -2.0, 0.0], [0.0, -1.0, -1.0], [-2.0, 0.0, -1.0]], [[-1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 0.0]])

    # Matrix left scaling; products contract indices, not entries independently.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(newComplex(2.0, 1.0)*a[n]) is MatrixObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(newComplex(2.0, 1.0)*a[n]) is SpinObject[T]
        c[n] := newComplex(2.0, 1.0)*a[n]
    checkMatrix(cField, [[1.0, 4.0, 0.0], [0.0, 3.0, 2.0], [4.0, 0.0, 2.0]], [[3.0, 2.0, 0.0], [0.0, -1.0, 1.0], [2.0, 0.0, 1.0]])

    # Matrix right scaling; products contract indices, not entries independently.
    within Accelerator:
      let a = aField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(a[n]*newComplex(2.0, 1.0)) is MatrixObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(a[n]*newComplex(2.0, 1.0)) is SpinObject[T]
        c[n] := a[n]*newComplex(2.0, 1.0)
    checkMatrix(cField, [[1.0, 4.0, 0.0], [0.0, 3.0, 2.0], [4.0, 0.0, 2.0]], [[3.0, 2.0, 0.0], [0.0, -1.0, 1.0], [2.0, 0.0, 1.0]])

    # Matrix product A B; products contract indices, not entries independently.
    within Accelerator:
      let a = aField.view(Read)
      let b = bField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(a[n]*b[n]) is MatrixObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(a[n]*b[n]) is SpinObject[T]
        c[n] := a[n]*b[n]
    checkMatrix(cField, [[2.0, 5.0, 2.0], [1.0, 3.0, 1.0], [0.0, 3.0, 3.0]], [[0.0, 1.0, 0.0], [-1.0, -1.0, 0.0], [0.0, 1.0, -2.0]])

    # Matrix product B A; products contract indices, not entries independently.
    within Accelerator:
      let a = aField.view(Read)
      let b = bField.view(Read)
      var c = cField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type T = typeof(aField).siteType
        static:
          doAssert typeof(b[n]*a[n]) is MatrixObject[Complex[D], 3]
          when T is SpinObject[T]: doAssert typeof(b[n]*a[n]) is SpinObject[T]
        c[n] := b[n]*a[n]
    checkMatrix(cField, [[2.0, 1.0, 2.0], [1.0, 4.0, 2.0], [2.0, 2.0, 2.0]], [[-2.0, -1.0, -1.0], [1.0, -2.0, 0.0], [0.0, 0.0, 1.0]])

    # Matrix-vector multiplication returns a vector of the corresponding shape
    # and tag. This pair check is additional to either operand's own concept.
    within Accelerator:
      let a = aField.view(Read)
      let x = xField.view(Read)
      var y = yField.view(WriteDiscard)
      parallel for n in lattice.sites(Packed):
        type V = typeof(xField).siteType
        static:
          doAssert typeof(a[n]*x[n]) is VectorObject[Complex[D], 3]
          when V is SpinObject[V]: doAssert typeof(a[n]*x[n]) is SpinObject[V]
        y[n] := a[n]*x[n]
    checkVector(yField, [4.0, 0.0, 1.0], [0.0, -1.0, 4.0])

    within Host:
      var c = cField.view(ReadWrite)
      parallel for n in lattice.sites(Packed): c[n][0, 2] := newComplex(4.0, -3.0)
    checkMatrix(cField, [[2.0, 1.0, 4.0], [1.0, 4.0, 2.0], [2.0, 2.0, 2.0]], [[-2.0, -1.0, -3.0], [1.0, -2.0, 0.0], [0.0, 0.0, 1.0]])
    checkMatrix(aField, mARe, mAIm)
    checkMatrix(bField, mBRe, mBIm)

  exerciseMatrices(matrixFieldA, matrixFieldB, matrixFieldC, vectorFieldA, vectorFieldC)
  exerciseMatrices(spinMatrixFieldA, spinMatrixFieldB, spinMatrixFieldC,
                   spinVectorFieldA, spinVectorFieldC)

  # Canonical nested spin-colour structures retain distinct tensor levels.
  type
    ColourVector = Vector[Complex[D], 3]
    ColourMatrix = Matrix[Complex[D], 3]
    Fermion = Spin[Vector[ColourVector, 4]]
    Propagator = Spin[Matrix[ColourMatrix, 4]]
  static:
    doAssert Fermion is SpinObject[Vector[ColourVector, 4]]
    doAssert Propagator is SpinObject[Matrix[ColourMatrix, 4]]
  let fermionA = lattice.newField(Fermion)
  let fermionB = lattice.newField(Fermion)
  let propagatorA = lattice.newField(Propagator)
  let propagatorB = lattice.newField(Propagator)
  let propagatorC = lattice.newField(Propagator)

  within Accelerator:
    var f = fermionA.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      for spin in 0..<4:
        for colour in 0..<3:
          f[n][spin][colour] := newComplex(float64(10*spin + colour + 1), float64(spin - colour))

  # A colour matrix acts on each spin component, without flattening spin/colour.
  within Accelerator:
    let matrix = matrixFieldA.view(Read)
    let f = fermionA.view(Read)
    var g = fermionB.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      for spin in 0..<4: g[n][spin] := matrix[n]*f[n][spin]
  within Host:
    let g = fermionB.view(Read)
    for n in lattice.sites(Scalar):
      for spin in 0..<4:
        for row in 0..<3:
          var expectedRe, expectedIm: float64
          # Independent small reference calculation over the literal matrix.
          for col in 0..<3:
            let fr = float64(10*spin + col + 1)
            let fi = float64(spin - col)
            expectedRe += mARe[row][col]*fr - mAIm[row][col]*fi
            expectedIm += mARe[row][col]*fi + mAIm[row][col]*fr
          closeTo(g[n][spin][row], expectedRe, expectedIm)

  within Accelerator:
    let f = fermionA.view(Read)
    var g = fermionB.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(2.0*f[n] + f[n]) is SpinObject[Fermion]
      g[n] := 2.0*f[n] + f[n]
  within Host:
    var g = fermionB.view(ReadWrite)
    parallel for n in lattice.sites(Scalar): g[n][2][1] += newComplex(3.0, -2.0)
  within Host:
    let g = fermionB.view(Read)
    for n in lattice.sites(Scalar):
      for spin in 0..<4:
        for colour in 0..<3:
          let selected = spin == 2 and colour == 1
          closeTo(g[n][spin][colour],
            float64(3*(10*spin + colour + 1) + (if selected: 3 else: 0)),
            float64(3*(spin - colour) - (if selected: 2 else: 0)))

  within Accelerator:
    var a = propagatorA.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      for s in 0..<4:
        for t in 0..<4:
          for i in 0..<3:
            for j in 0..<3:
              a[n][s, t][i, j] := newComplex(float64((s+1)*(t+2) + 3*i + j), float64(s-t+i-j))
  within Accelerator:
    let a = propagatorA.view(Read)
    var b = propagatorB.view(WriteDiscard)
    parallel for n in lattice.sites(Packed): b[n] := a[n]
  within Accelerator:
    let a = propagatorA.view(Read)
    let b = propagatorB.view(Read)
    var c = propagatorC.view(WriteDiscard)
    parallel for n in lattice.sites(Packed):
      static: doAssert typeof(2.0*a[n] + b[n]) is SpinObject[Propagator]
      c[n] := 2.0*a[n] + b[n]

  # Numeric division remains available at a matrix's numeric leaf.
  within Host:
    let a = propagatorA.view(Read)
    var c = propagatorC.view(ReadWrite)
    parallel for n in lattice.sites(Scalar):
      c[n][1, 2][0, 1] := a[n][1, 2][0, 1] / newComplex(1.0, 1.0)
  within Host:
    let a = propagatorA.view(Read)
    let b = propagatorB.view(Read)
    let c = propagatorC.view(Read)
    for n in lattice.sites(Scalar):
      for s in 0..<4:
        for t in 0..<4:
          for i in 0..<3:
            for j in 0..<3:
              let r = float64((s+1)*(t+2) + 3*i + j)
              let q = float64(s-t+i-j)
              closeTo(a[n][s, t][i, j], r, q)
              closeTo(b[n][s, t][i, j], r, q)
              if s == 1 and t == 2 and i == 0 and j == 1:
                closeTo(c[n][s, t][i, j], 3.5, -5.5)
              else: closeTo(c[n][s, t][i, j], 3.0*r, 3.0*q)

  # Permissions apply recursively, and tensor division has no implicit meaning.
  doAssert not compiles(block:
    within Host:
      let f = fermionA.view(Read)
      for n in lattice.sites(Scalar): f[n][0][0] := 0.0)
  doAssert not compiles(block:
    within Host:
      var f = fermionA.view(WriteDiscard)
      for n in lattice.sites(Scalar): f[n][0][0] += 1.0)
  doAssert not compiles(block:
    within Host:
      var p = propagatorA.view(WriteDiscard)
      for n in lattice.sites(Scalar): discard p[n][0, 0][0, 0].re)
  doAssert not compiles(block:
    within Host:
      let a = matrixFieldA.view(Read)
      let b = matrixFieldB.view(Read)
      for n in lattice.sites(Scalar): discard a[n] / b[n])

  let wrongShape = lattice.newField(Vector[Complex[D], 2])
  doAssert not compiles(block:
    within Host:
      let a = wrongShape.view(Read)
      var c = vectorFieldC.view(WriteDiscard)
      for n in lattice.sites(Scalar): c[n] := a[n])

  # A component proxy cannot outlive the View from which it was selected.
  within Host:
    var checkedLifetime = false
    for n in lattice.sites(Scalar):
      let escaped = block:
        let view = fermionA.view(Read)
        view[n][0][0]
      var rejected = false
      try: discard escaped.re
      except ValueError: rejected = true
      doAssert rejected
      checkedLifetime = true
      break
    doAssert checkedLifetime
