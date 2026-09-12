#!/usr/bin/env bash

# bootstrap.sh — install Quark's backend dependencies.
#
# build: build/bootstrap.sh
# Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>
#
# This is the first of the three steps in a Quark build:
#
#   ./bootstrap <backend>   obtain and build a backend and its dependencies
#   ./configure             discover what bootstrap installed, generate build files
#   make <target>           compile a Quark program
#
# Bootstrapping precedes configuration because configure's job is to read back
# how each backend was actually built; the backend has to exist first. This is
# the same order Grid and QEX use in their own repositories.
#
# One invocation may bootstrap several backends, which is what makes it
# possible to compile the same Quark source against each of them and compare.
# Each '--backend' opens a new backend, and every backend installs into its own
# dependency prefix and install directory under a shared prefix, so no two of
# them can disturb each other.
#
# Usage:
#   ./bootstrap [GLOBAL OPTIONS] --backend <backend> [BACKEND OPTIONS]
#                                [--backend <backend> [BACKEND OPTIONS]]...
#
# Backend selector strings are the ones accepted at compile time by
# src/quark/backend/backend.nim, so the name used here is the name used in
# '-d:backend=...'.
#
# Copyright (c) 2026 Curtis Taylor Peterson
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail

BUILD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
QUARK_ROOT="$(dirname "$BUILD_DIR")"

# ── Backend selectors ─────────────────────────────────────────────────────
# Canonical names, and the script that bootstraps each one. These must stay in
# step with the selector strings in src/quark/backend/backend.nim.
canonical_backend() {
    local name="${1,,}"
    name="${name//_/ }"
    name="${name//-/ }"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    case "$name" in
        qex|"quantum expressions")
            echo "qex" ;;
        grid)
            echo "grid" ;;
        quda)
            echo "quda" ;;
        *)
            echo "" ;;
    esac
}

backend_script() {
    case "$1" in
        qex)  echo "${BUILD_DIR}/qex.py" ;;
        grid) echo "${BUILD_DIR}/grid.py" ;;
        quda) echo "${BUILD_DIR}/quda.py" ;;
        *)    echo "" ;;
    esac
}

usage() {
    cat <<'USAGE'
Quark bootstrap — install a backend and everything it depends on.

Usage:
  ./bootstrap [GLOBAL OPTIONS] --backend <backend> [BACKEND OPTIONS]
                               [--backend <backend> [BACKEND OPTIONS]]...

Backends:
  grid     Grid, built from source along with GMP, MPFR, FFTW, OpenSSL,
           HDF5, c-lime, and libunwind
  qex      QEX, checked out and configured against QMP and QIO, optionally
           with a CUDA, HIP, or SYCL backend and against Grid or QUDA
  quda     QUDA, built with CMake for a CUDA, HIP, or SYCL target

  Every spelling that src/quark/backend/backend.nim accepts works here, so
  the name given to bootstrap is the name given to '-d:backend=...'.

Global options:
  Any option accepted by the backend scripts may be given before the first
  --backend, in which case it applies to every backend in the invocation.
  A backend's own options override it. Options shared by all backends:

  --prefix DIR       Install everything under DIR (default: <quark>/local)
  --jobs, -j N       Parallel make jobs
  --skip-deps        Do not build dependencies
  --use-spack        Install dependencies through a private Spack clone
  --no-llvm          Use the system compiler instead of LLVM/Clang
  --skip-nim         Use $NIM or the nim on PATH instead of installing one

  -h, --help                Show this message
  --backend <name> --help   Show every option for that backend

Examples:
  # One backend
  ./bootstrap --backend grid --simd AVX2 --comms mpi-auto

  # Two backends, sharing a prefix and a job count, each with its own options
  ./bootstrap --jobs 16 --backend grid --simd AVX2 \
                        --backend qex --simd SSE,AVX --vlen 8

  # Three backends with their defaults
  ./bootstrap --backend grid --backend qex --backend quda

  # A QEX that itself solves through Grid and QUDA
  ./bootstrap --backend grid --backend quda \
              --backend qex --with-grid --with-quda

After bootstrapping, run ./configure and then make.
USAGE
}

die() {
    echo "bootstrap: $*" >&2
    exit 1
}

# ── Check the tools every backend build needs ────────────────────────────
require_tools() {
    local missing=()
    for tool in python3 git curl make tar; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        die "missing required tools: ${missing[*]}"
    fi
}

# ── Parse the command line ───────────────────────────────────────────────
# Everything before the first backend name is global and is prepended to each
# backend's own options, so a backend's options win on conflict.
GLOBAL_OPTS=()
SEGMENTS=()          # one entry per backend: a newline-delimited argv list

parse_arguments() {
    local args=("$@")
    local i=0
    local n=${#args[@]}
    local current=""

    while [ $i -lt $n ]; do
        local arg="${args[$i]}"

        case "$arg" in
            -h|--help)
                # Before any --backend this is the driver's own help; after one
                # it belongs to that backend and is forwarded there.
                if [ -z "$current" ] && [ ${#SEGMENTS[@]} -eq 0 ]; then
                    usage
                    exit 0
                fi
                ;;
        esac

        # '--backend NAME' and '--backend=NAME' both open a new backend.
        local name=""
        case "$arg" in
            --backend=*)
                name="${arg#*=}"
                ;;
            --backend)
                i=$((i + 1))
                [ $i -lt $n ] || die "--backend needs a backend name"
                name="${args[$i]}"
                ;;
        esac

        if [ -n "$name" ]; then
            local canonical
            canonical="$(canonical_backend "$name")"
            [ -n "$canonical" ] || \
                die "unknown backend '$name'. Run '$0 --help' for the list."
            [ -n "$current" ] && SEGMENTS+=("$current")
            current="$canonical"
            i=$((i + 1))
            continue
        fi

        if [ -z "$current" ]; then
            GLOBAL_OPTS+=("$arg")
        else
            current="${current}"$'\n'"${arg}"
        fi
        i=$((i + 1))
    done

    [ -n "$current" ] && SEGMENTS+=("$current")

    if [ ${#SEGMENTS[@]} -eq 0 ]; then
        usage
        die "no backend given; name one with --backend"
    fi
}

# ── Run one backend segment ──────────────────────────────────────────────
run_segment() {
    local segment="$1"
    local -a parts=()
    while IFS= read -r line; do parts+=("$line"); done <<< "$segment"

    local backend
    backend="$(canonical_backend "${parts[0]}")"
    local script
    script="$(backend_script "$backend")"

    if [ -z "$script" ]; then
        die "backend '$backend' is recognised by Quark but has no bootstrap script yet.
       Supported backends: grid, qex, quda"
    fi
    [ -f "$script" ] || die "missing backend script: $script"

    local -a opts=()
    if [ ${#parts[@]} -gt 1 ]; then
        opts=("${parts[@]:1}")
    fi

    # A backend's --help is its own, not the driver's.
    for opt in ${opts[@]+"${opts[@]}"}; do
        case "$opt" in
            -h|--help) exec python3 "$script" --help ;;
        esac
    done

    echo ""
    echo "=================================================================="
    echo " Bootstrapping backend: $backend"
    echo "=================================================================="
    python3 "$script" ${GLOBAL_OPTS[@]+"${GLOBAL_OPTS[@]}"} ${opts[@]+"${opts[@]}"}
}

main() {
    [ $# -gt 0 ] || { usage; exit 1; }
    parse_arguments "$@"
    require_tools

    local -a done_backends=()
    for segment in "${SEGMENTS[@]}"; do
        run_segment "$segment"
        done_backends+=("$(canonical_backend "$(head -n1 <<< "$segment")")")
    done

    echo ""
    echo "=================================================================="
    echo " Bootstrap complete: ${done_backends[*]}"
    echo ""
    echo " Next:  ./configure"
    echo "        make <target>"
    echo "=================================================================="
}

main "$@"
