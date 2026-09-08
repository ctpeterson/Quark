# Installing Quark

Quark is an ordinary Nim package. Once a machine has a backend built and
configured, `import quark` works in any Nim file, and any library can depend
on Quark without carrying a build system of its own.

Getting there takes three steps, in the order C and C++ projects in this field
already use:

| Step | Command | What it does |
| --- | --- | --- |
| 1 | `./bootstrap --backend <name>` | Obtains and builds a backend and its dependencies |
| 2 | `./configure` | Reads back how each backend was built, writes the build directory |
| 3 | `make <target>`, or `nimble install` | Compiles a program, or installs Quark as a package |

Bootstrapping comes before configuration because configure's job is to read
back how each backend was *actually* built; the backend has to exist first.
Grid and QEX order their own builds the same way.

## Step 1 — bootstrap a backend

```
./bootstrap --backend grid
```

This downloads, builds, and installs Grid together with GMP, MPFR, FFTW,
OpenSSL, HDF5, c-lime, and libunwind, plus a Nim toolchain. It takes a while
the first time and is resumable: anything already installed is skipped.

The three backends are:

| Backend | What bootstrap does |
| --- | --- |
| `grid` | Builds Grid and its seven C/C++ dependencies |
| `qex` | Builds QMP and QIO, checks out QEX, runs QEX's own `configure` |
| `quda` | Builds QUDA with CMake for a CUDA, HIP, or SYCL target |

Backend names are the ones `src/quark/backend/backend.nim` accepts, so the
name given to `--backend` is the name later given to `-d:backend=...`.

### Several backends at once

Compiling one Quark source against every backend is the point of the project,
so one invocation can bootstrap several. Each `--backend` opens a new one:

```
./bootstrap --jobs 16 --backend grid --simd AVX2 \
                      --backend qex --simd SSE,AVX --vlen 8
```

Options given before the first `--backend` apply to all of them; a backend's
own options override them. Each backend gets its own dependency prefix and
install directory, so backends never disturb each other — which matters,
because QIO ships a `liblime` that would otherwise collide with the c-lime
Grid needs.

### GPU builds

Every backend can be built for a GPU.

```
# Grid on NVIDIA hardware
./bootstrap --backend grid --simd GPU --accelerator cuda --cxx nvcc

# QUDA for Ampere, with multigrid
./bootstrap --backend quda --gpu-arch sm_80 --enable-multigrid

# QEX with its CUDA backend, compiled through QEX's own nvcc wrapper
./bootstrap --backend qex --accelerator cuda --cuda-arch sm_90
```

QEX selects its accelerator with the compile-time define `-d:Backend=CUDA`,
`HIP`, `SYCL`, or `OpenMP`, which `--accelerator` sets. CUDA is compiled
through the `ccwrapper` script in QEX's own tree, which drives `nvcc` with the
host compiler and GPU architecture taken from the environment; `--cuda-arch`,
`--cuda-dir`, `--nvcc`, and `--cuda-host-compiler` fill those in.

Note that QEX's `-d:Backend` and Quark's `-d:backend` are different defines.
QEX's chooses how QEX runs its own kernels; Quark's chooses which adapter
Quark lowers through.

### Backends stacked on backends

QEX can itself solve through Grid or QUDA. Bootstrap those first and QEX picks
them up from the same prefix:

```
./bootstrap --backend grid --backend quda \
            --backend qex --with-grid --with-quda
```

`--with-grid` and `--with-quda` accept a path if the installation is elsewhere.
Either implies a C++ build, since Grid and QUDA are C++.

### Common options

```
--prefix DIR       Install everything under DIR (default: ./local)
--jobs, -j N       Parallel make jobs
--skip-deps        Do not build dependencies; they are installed elsewhere
--use-spack        Install dependencies through a private Spack clone
--no-llvm          Use the system compiler instead of downloading LLVM/Clang
--skip-nim         Use $NIM or the nim on PATH instead of installing one
```

Every backend has many more. Run `./bootstrap --backend grid --help`, and the
same for `qex` and `quda`, for the full list.

If a dependency fails to build from source, bootstrap falls back to installing
it through a private Spack clone — always its own, never a Spack already on
the machine.

### What bootstrap produces

```
local/
    src/            source and download trees, shared across backends
    deps/grid       GMP, MPFR, FFTW, OpenSSL, HDF5, c-lime, libunwind
    deps/qex        QMP, QIO
    nim/            Nim toolchain
    grid/           Grid install prefix, including bin/grid-config
    qex/            QEX build directory, including qexconfig.nims
    quda/           QUDA install prefix
    bootstrap.json  manifest of every backend installed so far
```

`bootstrap.json` is the handoff to `configure`. It accumulates: bootstrapping
a second backend leaves the first one's entry intact.

Each backend also leaves behind the record of how it was built — Grid's
`bin/grid-config`, QEX's `qexconfig.nims`, QUDA's `CMakeCache.txt`. Every MPI,
OpenMP, SIMD, and accelerator decision is already in those files, and
`configure` reads them rather than deriving any of it a second time.

## Step 2 — configure

```
./configure
```

Configure derives nothing it can read. Each backend already records how it was
built — Grid in `bin/grid-config`, QEX in `qexconfig.nims`, QUDA in
`CMakeCache.txt` — and configure reads those, together with `bootstrap.json`,
into one file:

```
# Quark build configuration
default.backend = grid
nim = /home/me/quark/local/nim/bin/nim

[grid]
prefix   = /home/me/quark/local/grid
language = cpp
passC    = -I/home/me/quark/local/grid/include -fno-strict-aliasing
passL    = -L/home/me/quark/local/grid/lib -Wl,-rpath,/home/me/quark/local/grid/lib -lGrid
nimFlags = --path:...
```

Keys before any section are global; a section per backend carries its
settings. `passC` and `passL` travel with Quark's source as pragmas, so they
reach any project that imports Quark. `nimFlags` are the settings Nim only
accepts on its command line — search paths, defines, environment variables —
so they are applied by the generated `Makefile` instead.

Configure writes that file, a `Makefile`, and the build script behind it into
the **build directory**, and everything a build produces lands there too. The
build directory is `local/` by default — where bootstrap installed — so the
source tree stays clean:

```
local/
    quark.conf      the configuration Quark reads
    quark.nims      the Nim configuration a project outside this one includes
    Makefile        run make from here
    Makefile.nims   the build script it hands its work to
    bin/            compiled programs
    nimcache/       generated C or C++ and object files
```

`--build-dir DIR` puts them somewhere else, and several build directories can
exist against one checkout, which is how one source tree is built for more
than one machine or SIMD target:

```
./configure --build-dir ~/builds/quark-avx2
./configure --build-dir ~/builds/quark-gpu
```

Given `--user`, configure also installs the configuration to
`~/.config/quark/config`, where a Quark installed with Nimble looks for it.

Useful options:

```
--backend NAME     Backend an 'import quark' with no -d:backend uses
--user             Also install to ~/.config/quark/config
--show             Print the configuration instead of writing it
--only NAME        Configure only this backend
--grid-prefix P    Configure a backend built by hand, with no manifest
--qex-prefix P     (likewise for QEX)
--quda-prefix P    (likewise for QUDA)
```

A backend built outside bootstrap needs no manifest: point configure at its
prefix and it reads that backend's own build record the same way.

## Step 3 — build a program, or install the package

### Building in the repository

`make` compiles one program by name, the way QEX and Grim build individual
scripts. Targets are searched for under `src`, `tests`, `oracle`, and
`examples`, so the name is the one the program is spoken about by.

Run it from the build directory:

```
cd local

make list                      # every program make can build
make oracleA                   # compiles oracle/oracleA.nim to bin/oracleA
make oracleA BACKEND=grid      # against a particular backend
make oracleA VERBOSE=1         # reporting what it is built against
make oracleA DEBUG=1           # unoptimised, for debugging
make clean
```

From anywhere else, `make -C /path/to/build <target>` does the same.

Builds are optimised by default: `make <target>` compiles with `-d:release`,
since an unoptimised lattice program is only useful for debugging. Say
otherwise with `DEBUG=1` for an unoptimised build with native debugging
information, or `DANGER=1` to go past release and remove the runtime checks
release keeps. `RELEASE=1` is accepted but needs no passing.

Any explicit choice on the Nim command line wins over the default, including
one passed through `ARGS`, so `make oracleA ARGS=--opt:none` is unoptimised
and `ARGS=-d:danger` does not also get `-d:release`.

The backend comes from `default.backend` unless `BACKEND=` or `-d:backend=`
overrides it, and whether Quark compiles as C or C++ follows the backend's
`language`. `ARGS="..."` passes anything else through to Nim.

Without `make` — before configure has run, or from another directory — the
same build is one command:

```
nim c --path:src -d:backend=qex oracle/oracleA.nim
```

The adapters are portable Nim, so this needs no backend installed. What a
backend installation adds is the flags to link against it, which is what
`configure` and `make` supply.

### Installing the package

To use Quark from outside the repository, install it:

```
nimble install
```

Then an ordinary Nim project depends on it the way it would on any package:

```nim
# mysim.nimble
requires "quark >= 0.1.0"
```

```nim
# mysim.nim
import quark
```

```
nimble c mysim.nim
```

No build system, no flags. This works because Quark carries its backend flags
in its own source rather than in a Makefile:
`src/quark/build/configuration.nim` finds the machine's configuration at
compile time, and `src/quark/backend/backend.nim` turns the selected backend's
entry into `passC` and `passL` pragmas.

Run `./configure --user` once so that projects outside this checkout can find
the configuration.

### Choosing the backend

`-d:backend=NAME` selects the adapter Quark lowers through, and accepts the
same spellings `--backend` does. When it is not given, the `default.backend`
in the configuration is used, which is what lets `import quark` compile with
no flags at all. Compiling one source against every backend in turn is then
just:

```
nim c -d:backend=grid mysim.nim
nim c -d:backend=qex  mysim.nim
```

### Where the configuration is found

In order, first hit wins:

1. `-d:quarkConfig=PATH`
2. `$QUARK_CONFIG`
3. `<quark checkout>/local/quark.conf`, so a source checkout needs no setup
4. `~/.config/quark/config`, which is what an installed Quark uses

An absent configuration is not an error: Quark's portable interface compiles
without one, and only a backend that needs flags to link reports the omission.

To see what a machine resolves:

```
nimble config
```

### Reporting the build configuration while compiling

`-d:quarkVerbose` makes any Quark compile report what it is being built
against, which is the provenance of the resulting binary:

```
nim c --path:src -d:backend=qex -d:quarkVerbose oracle/oracleA.nim
make oracleA VERBOSE=1
```

```
Quark build configuration
  config           /home/me/quark/local/quark.conf
  default.backend  qex
  nim              /home/me/quark/local/nim/bin/nim
  bootstrap        /home/me/quark/local/bootstrap.json
  configured       2026-09-08T13:21:06-04:00
  prefix           /home/me/quark/local
  available        qex

  backend          qex
    prefix       /home/me/quark/local/qex
    language     cc
    passC        -I/home/me/quark/local/deps/qex/include
    passL        -L/home/me/quark/local/deps/qex/lib ... -lqmp -lqio -llime
    nimFlags     --path:/home/me/quark/local/src/qex/src ...
    accelerator  CPU
    branch       devel
    cc           mpicc
    comms        mpi
    repo         https://github.com/jcosborn/qex.git
    ...
```

Everything below the backend name is what `configure` read back from how that
backend was actually built, including the facts `bootstrap` recorded in
`bootstrap.json` — the repository and branch, the compilers, the
communications and accelerator choices, and the SIMD settings. The report is
generated from whatever the configuration contains rather than a fixed list,
so a fact bootstrap learns to record appears here without anything else
changing.

It also reports honestly when there is nothing to report: with no
configuration it says so, and when the selected backend is one this machine
has not built it says that the build is proceeding without that backend's
flags.

### Settings that cannot travel in Quark's source

`passC` and `passL` become pragmas in Quark's own source, so an installed
Quark links its backend correctly anywhere with no help. Some settings cannot
work that way, because Nim only accepts them on its command line:

- search paths, for a backend whose adapter compiles against that backend's
  own Nim modules;
- defines that the backend's own modules read, such as QEX's `qmpDir` and
  `qioDir`, from which QEX emits its own link flags;
- the compiler executable, since QEX links MPI through `mpicc` rather than
  through a library flag;
- environment variables read during compilation, such as QEX's `VLEN`; and
- Nim's own `--threads`, `--tlsEmulation`, and `--mm`, which a backend's
  threading and memory model depend on.

Grid and QUDA are C++ libraries and need none of this: their flags travel with
Quark's source. QEX is a Nim framework, so it does.

Configure writes them as `nimFlag` entries in `quark.conf`, one per line since
a compiler flag list contains spaces, and renders the same list as a Nim
configuration in `quark.nims`. Inside the build directory the `Makefile`
applies them. A project elsewhere adds one line to its own `config.nims`:

```nim
include "/home/me/.config/quark/quark.nims"
```

`./configure --user` puts that file at the stable path above, and configure
prints the exact line to paste. With it, an ordinary project builds against a
backend with nothing else to remember:

```
nim c -d:backend=qex mysim.nim
```

The file selects on `-d:backend=` exactly as Quark does, so one include serves
every backend the machine has.
