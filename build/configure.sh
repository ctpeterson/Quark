#!/usr/bin/env bash

# configure.sh — turn what bootstrap installed into Quark's build configuration.
#
# build: build/configure.sh
# Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>
#
# This is the second of the three steps in a Quark build:
#
#   ./bootstrap --backend <name>   obtain and build a backend
#   ./configure                    read back how it was built, write the config
#   make <target>                  compile a Quark program
#
# Configure derives nothing it can read. Grid records its build in
# bin/grid-config, QEX in qexconfig.nims, QUDA in CMakeCache.txt, and configure
# reads those rather than working out compiler flags a second time.
#
# Usage:
#   ./configure [OPTIONS]
#
# Run './configure --help' for the full list of options.
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

command -v python3 >/dev/null 2>&1 || {
    echo "configure: python3 is required but was not found." >&2
    exit 1
}

exec python3 "${BUILD_DIR}/configure.py" "$@"
