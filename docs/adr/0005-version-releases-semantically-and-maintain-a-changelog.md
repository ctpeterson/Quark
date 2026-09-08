---
status: accepted
---

# Version releases semantically and maintain a changelog

Quark releases follow Semantic Versioning, use the `version` field in `quark.nimble` as their single version source, and are tagged `vX.Y.Z` only after the corresponding release commit passes verification. `CHANGELOG.md` records notable user-facing changes under `Unreleased`; a release moves those entries under its version and date. During initial development, `0.MINOR.0` marks a changed portable contract or substantial new capability and `0.MINOR.PATCH` marks compatible fixes, documentation, or build improvements; `1.0.0` will declare the portable interface stable.

The process remains manual while Quark's release cadence is low. This keeps version decisions reviewable and avoids deriving compatibility promises from commit syntax; automation can be introduced when repeated releases demonstrate which parts are mechanical.
