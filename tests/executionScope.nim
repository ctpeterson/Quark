import std/unittest
import quark
include support/siteIndices

static:
  doAssert not compiles(block:
    let field = newLattice([8, 8]).newField(Real[D])
    discard field.view(Read))
  doAssert not compiles(block:
    let field = newLattice([8, 8]).newField(Real[D])
    var view: FieldView[Real[D], Read]
    within Host: view = field.view(Read)
    for site in field.lattice.sites(Scalar): discard view[site])
  doAssert not compiles(block:
    let lattice = newLattice([8, 8])
    parallel for site in lattice.sites(Scalar): discard site)

suite "Execution Context and view lifetime":
  test "within introduces a lexical scope":
    within Host:
      let localView = newLattice([8, 8]).newField(Real[D]).view(Read)
      discard localView
    static: doAssert not declared(localView)

  test "escaped view copies are invalid after their owning scope":
    let lattice = newLattice([8, 8])
    let field = lattice.newField(Real[D])
    var escaped: FieldView[Real[D], Read]
    within Host:
      let view = field.view(Read)
      escaped = view
      for site in lattice.sites(Scalar): discard escaped[site]
    within Host:
      for site in lattice.sites(Scalar):
        expect ValueError: discard escaped[site]

  test "exception unwinding closes views":
    let lattice = newLattice([8, 8])
    let field = lattice.newField(Real[D])
    var escaped: FieldView[Real[D], Read]
    expect IOError:
      within Accelerator:
        escaped = field.view(Read)
        raise newException(IOError, "body failed")
    within Accelerator:
      for site in lattice.sites(Packed):
        expect ValueError: discard escaped[site]

  test "inner declarations close at their lexical scope":
    let lattice = newLattice([8, 8])
    let field = lattice.newField(Real[D])
    within Host:
      var escaped: FieldView[Real[D], Read]
      block:
        let view = field.view(Read)
        escaped = view
      for site in lattice.sites(Scalar):
        expect ValueError: discard escaped[site]

  test "nested contexts retain the outer view and reject wrong placement":
    let lattice = newLattice([8, 8])
    let field = lattice.newField(Real[D])
    within Host:
      let outer = field.view(Read)
      within Accelerator:
        let inner = field.view(Read)
        for site in lattice.sites(Scalar):
          discard inner[site]
          expect ValueError: discard outer[site]
      for site in lattice.sites(Scalar): discard outer[site]

  test "site proxies retain the lifetime of the view":
    let lattice = newLattice([8, 8])
    let field = lattice.newField(Real[D])
    type Proxy = typeof(block:
      within Host: field.view(Read)[firstScalar(lattice)])
    var escaped: Proxy
    within Host:
      let view = field.view(Read)
      escaped = view[firstScalar(lattice)]
      try:
        discard +escaped
        check false
      except ValueError as error:
        check error.msg == "Field site arithmetic is not implemented"
    try:
      discard +escaped
      check false
    except ValueError as error:
      check error.msg == "Field View is outside its lifetime"

  test "both placements support all static access modes":
    let lattice = newLattice([8, 8])
    let field = lattice.newField(Real[D])
    template checkContext(space: static ExecutionSpace) =
      within space:
        let read = field.view(Read)
        let write = field.view(WriteDiscard)
        let update = field.view(ReadWrite)
        discard read[firstScalar(lattice)]
        discard write[firstPacked(lattice)]
        discard update[firstScalar(lattice)]
    checkContext(Host)
    checkContext(Accelerator)
