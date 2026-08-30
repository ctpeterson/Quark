# Quark

Quark is a Nim-inspired language for lattice gauge and lattice field theory.
Its design goal is to make lattice programs easier to read, review, and deploy
than conventional HPC codebases without hiding the computational structure that
matters for performance and correctness.

## Design goals

- Nim-like surface syntax with explicit, readable control flow
- First-class lattice concepts instead of ad hoc array conventions
- A small type system that keeps data layout and intent visible
- Explicit serial and parallel loops
- Backend-selected code generation at compile time
- Lowering through a backend-neutral IR before emitting target code
- C as the portable compilation target, with Grid, QEX, and QUDA as primary
  backend families

## Compilation model

Quark source is **not** Nim, but the compiler can be implemented as a Nim
extension or alongside Nim tooling.

The intended lowering pipeline is:

1. Parse Quark source
2. Type-check and elaborate lattice constructs
3. Lower to a Quark IR that makes iteration spaces, field access, and
   communication boundaries explicit
4. Select a backend at compile time
5. Emit backend-oriented C

This keeps the user-facing syntax compact while preserving enough structure for
specialized backends:

- `grid` for Grid-oriented CPU/GPU lattice kernels
- `qex` for QEX-oriented code generation
- `quda` for QUDA-oriented accelerator code generation

## Core language sketch

### Lattice construct

The lattice is a first-class value describing geometry and decomposition.

```text
let lat = lattice([32, 32, 32, 64], simd = 4, layout = evenOdd)
```

Required lattice properties:

- global extents
- site indexing policy
- optional decomposition/layout metadata
- backend-visible parallel iteration space

Fields are parameterized by both the lattice and their element type:

```text
var U: gaugeField[lat, SU3]
var psi: fermionField[lat, SpinColor]
var action: real64
```

This makes code generation aware of geometry and field placement from the start.

### Simple type system

The initial type system should stay small and explicit:

#### Scalar types

- `bool`
- `int32`, `int64`
- `real32`, `real64`
- `complex32`, `complex64`

#### Domain types

- `lattice`
- `site`
- `direction`
- `SU2`, `SU3`
- `spinor[Nc]`
- `colorVector[Nc]`
- `gaugeLink[Group]`
- `field[L, T]`

#### Derived aliases

```text
type
  SpinColor = spinor[3]
  SU3Link = gaugeLink[SU3]
```

The type system should prefer a small number of built-in physics-oriented types
over a large generic hierarchy.

### Serial and parallel loops

Quark should make the difference between sequential host logic and site-parallel
work obvious in the syntax.

#### Serial loop

```text
for mu in 0 ..< 4:
  action += plaquette(U, mu)
```

This is used for scalar control flow, reductions that remain explicit, and other
host-side iteration.

#### Parallel loop

```text
pfor x in lat.sites:
  psi[x] = Dslash(U, psi, x)
```

The `pfor` form denotes lattice-parallel execution over the backend-visible
iteration space. A Grid backend would lower this construct to
`ACCELERATOR_FOR`, while other backends can map it to their own accelerator or
threading primitives.

An explicit reduction form should remain visible rather than inferred:

```text
var norm: real64 = 0.0
reduce(+; norm) pfor x in lat.sites:
  yield inner(psi[x], psi[x]).re
```

Inside a `reduce` block, `yield` emits the per-iteration contribution, and the
combiner determines how those contributions are merged into the named result.

## Example

```text
backend grid

let lat = lattice([16, 16, 16, 32], layout = evenOdd)

var U: gaugeField[lat, SU3]
var psi: fermionField[lat, SpinColor]
var out: fermionField[lat, SpinColor]

pfor x in lat.sites:
  out[x] = zero(SpinColor)
  for mu in 0 ..< 4:
    out[x] += U[x, mu] * psi[shift(x, mu)]
```

This example keeps the computational details visible:

- the backend is chosen explicitly
- the lattice geometry is explicit
- the parallel loop is explicit
- the serial loop over directions is explicit

## Backend contract

Backends should consume the same IR but provide different lowering rules for:

- field storage layout
- site indexing/decomposition
- halo exchange and communication hooks
- accelerator loop emission
- math/runtime intrinsics

The frontend should therefore reject constructs that cannot be represented in
the IR with explicit data motion and iteration semantics.

## Initial implementation direction

The smallest practical implementation plan is:

1. Define the Quark grammar and AST around lattice declarations, field types,
   and `for`/`pfor`
2. Lower to a compact IR that records geometry, types, and loop intent
3. Emit C through selectable backend adapters for Grid, QEX, and QUDA
4. Use Nim as the implementation substrate for the compiler if it accelerates
   parser, IR, and code-emission work

That preserves the core philosophy: Quark should read better than traditional
lattice code without becoming so abstract that the machine model disappears.
