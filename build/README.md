# Quark build system

ADR 0004 defines the build contract. Shared orchestration lives in
`common.py` and `configure.py`; `grid_config.py`, `qex_config.py`, and
`quda_config.py` own the native configuration readers. QUDA configuration
supports dependency integration, but QUDA is not a selectable Quark adapter.

Run the offline fixture suite with:

```sh
python3 -m unittest discover -s tests -p 'test_build.py'
```

`nimble verify` runs this suite after checking the frozen oracles. The
fixtures exercise native setting extraction, real generated and installed
builds, explicit configuration binding, aliases, shell quoting, archive
integrity, repository resolution, and manifest/fallback recording.

Generated configurations use `format = 2`: each value other than the format
number is a JSON string. Repeated `nimFlag` keys preserve the argument list,
including trailing whitespace and escaped characters. The Nim reader still
accepts legacy unquoted files without a format marker. Generated Make builds
and `quark.nims` pass their exact absolute configuration path as
`-d:quarkConfig=...`; an explicit missing file rejects. Installing the user
configuration rebinds its include file to the installed copy.

QEX extraction accepts literal strings, numbers, sequences, prior-setting
references, concatenation, and the default directory expressions
`getCurrentDir()`, `getHomeDir()`, and path joining. Richer expressions
reject with the setting name rather than being omitted. Generated build
directories own their own output/cache locations.

Archive identities are pinned in `archives.json`. Fresh and cached downloads
are checked before extraction; an integrity error never triggers a Spack
fallback. Adding another Nim version requires adding reviewed archive entries.
The automatic binary downloads support Linux x86-64 and AArch64.

Checksum provenance (checked September 8, 2026; URL availability, cached hashes,
and backend source identities refreshed in the [September 12 closeout](../docs/notes/milestone-1-closeout.md)):

- Nim 2.2.8: upstream
  [x64 checksum](https://nim-lang.org/download/nim-2.2.8-linux_x64.tar.xz.sha256)
  and [ARM64 checksum](https://nim-lang.org/download/nim-2.2.8-linux_arm64.tar.xz.sha256).
- LLVM 18.1.8: the release builders' published hashes and filenames in the
  [upstream release thread](https://discourse.llvm.org/t/18-1-8-has-been-tagged/79726).
  All four toolchain archive URLs were checked with HTTP header requests.
- GMP, MPFR, FFTW, OpenSSL, HDF5, libunwind, QMP, and QIO: SHA-256 computed
  from the pinned upstream HTTPS archives named in the lock file. GMP uses
  the GNU release mirror. These are content pins, not signature attestations.

Backend `--*-branch` options accept branches, tags, or commit IDs. New
checkouts resolve to detached commits; requested updates must fast-forward.
`bootstrap.json` records commits, remotes, tracked patches, submodule status,
untracked filenames, available verified archives, and tool versions.
`resolutions.json` persists fallback reasons and concrete Spack specs across
resumed runs; these are copied into the backend's manifest entry. Source trees
and the manifest must be retained to inspect local or generated files.

The fixture suite does not replace a full native backend build or accelerator
acceptance run. It tests the build integration without requiring those large
dependencies or GPU hardware.
