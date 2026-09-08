---
status: accepted
---

# Treat build integration as a tested backend contract

Quark's bootstrap, configuration, and generated-build workflow is part of the portable-to-backend seam rather than incidental project scripting. Shared machinery owns orchestration and file formats, while each backend owns extraction and validation of its native build settings; generated builds bind explicitly to the configuration that produced them, canonicalize backend selectors consistently, preserve upstream settings without lossy parsing, and reject a backend that does not yet satisfy Quark's portable interface. This boundary prevents a convenient build wrapper from silently changing compiler, accelerator, layout, or linkage semantics.

## Consequences

- Milestone 1 includes fixture-based tests for backend configuration readers, generated files, custom and space-containing build paths, canonical selector aliases, QEX list-valued environment and Nim settings, and explicit rejection of unsupported adapters.
- A generated build passes its exact `quark.conf` to Quark source; checkout and user configuration discovery remain conveniences for direct Nim invocation, not a way for generated builds to select a different configuration accidentally.
- QUDA may be bootstrapped as a dependency of another backend, but `-d:backend=quda` remains unsupported until a conforming QUDA adapter exists.
- Supported toolchain artifact locations are tested, archives are verified cryptographically, mutable repositories are resolved to commits, and the manifest records those identities. A fallback that changes the resolved dependency graph is reported and recorded.
- Backend-specific configuration readers live with their backend integration. Shared configuration code coordinates them and emits the common Quark format.
