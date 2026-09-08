# Changelog

All notable changes to Quark are recorded here. The format is based on [Keep a Changelog](https://keepachangelog.com/), and releases follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Backend-neutral `Geometry`, `Partition`, and `Lattice` interfaces with QEX and Grid conformance scaffolds.
- Portable numeric kinds, precisions, closed arithmetic capabilities, and mixed-kind promotion.
- A frozen Oracle B contract for provenance-carrying lattice Decompositions and Domains.
- Compile-time backend selection and an experimental bootstrap, configure, and generated-Makefile workflow for backend toolchains.
- Compile-time reporting of the selected build configuration.
- Focused lattice and numeric conformance tests run against both QEX and Grid by `nimble verify`.

### Changed

- Organized portable interfaces, backend adapters, and build configuration under explicit `base`, `backend`, and `build` seams.
- Standardized Nim source headers and added native documentation comments for settled portable interfaces.
- Recorded build-system hardening as a Milestone 1 requirement in ADR 0004.

### Fixed

- Restored the frozen Oracle A checksum and added Oracle B to the freeze manifest.
