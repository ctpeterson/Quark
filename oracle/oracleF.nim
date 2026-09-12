# Execution intent oracle for Milestone 2 Step 3, independent of Field storage.
# Inspect expanded/generated code for each of the four loops: Host uses the
# selected backend's native host parallel loop, Accelerator its accelerator loop.
# The bodies have no shared counters or host-memory captures on an accelerator.
# Native iteration execution/coverage needs backend probes and, cumulatively,
# Oracle A's observable nonuniform Field transformations; this file is not a
# substitute for that numerical evidence.

import quark

quark:
  let lattice: Lattice = [8, 8, 8, 16].newLattice()
  within Host:
    doAssert executionSpace() == Host
    parallel for n in lattice.sites(Scalar):
      static:
        doAssert n is ScalarSite[typeof(lattice)]
        doAssert executionSpace() == Host
      discard n.index
    parallel for n in lattice.sites(Packed):
      static:
        doAssert n is PackedSite[typeof(lattice)]
        doAssert executionSpace() == Host
      discard n.index
    within Accelerator:
      doAssert executionSpace() == Accelerator
      parallel for n in lattice.sites(Scalar):
        static:
          doAssert n is ScalarSite[typeof(lattice)]
          doAssert executionSpace() == Accelerator
        discard n.index
      parallel for n in lattice.sites(Packed):
        static:
          doAssert n is PackedSite[typeof(lattice)]
          doAssert executionSpace() == Accelerator
        discard n.index
    doAssert executionSpace() == Host

  doAssert not compiles(executionSpace())
  doAssert not compiles(block:
    parallel for n in lattice.sites(Scalar): discard n.index)
