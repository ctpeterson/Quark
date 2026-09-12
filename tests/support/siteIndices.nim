# Obtain indices through the portable iterator; never fabricate provenance.
type
  ScalarIndex = ScalarSite[typeof(newLattice([8, 8]))]
  PackedIndex = PackedSite[typeof(newLattice([8, 8]))]

proc firstScalar[L: Lattice](lattice: L): auto =
  for site in lattice.sites(Scalar): return site
  raise newException(ValueError, "fixture requires a scalar site")

proc firstPacked[L: Lattice](lattice: L): auto =
  for site in lattice.sites(Packed): return site
  raise newException(ValueError, "fixture requires a packed site")
