#[
Backend selector module

src: quark/backend/backend.nim
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

MIT License

Copyright (c) 2026 Curtis Taylor Peterson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]#

import ../build/configuration
export configuration

const backend* {.strdefine.} = quarkDefaultBackend
  ## The backend Quark lowers through, selected with `-d:backend=NAME`.
  ##
  ## A machine that has been configured supplies the default, so that an
  ## ordinary Nim file can `import quark` and compile with no build system of
  ## its own. Passing `-d:backend=` always overrides that default, which is
  ## what lets one source be compiled against every backend in turn.

const selectedBackend* = quarkCanonicalBackend(backend)
  ## `backend` reduced to its canonical name, empty when it names no backend.

when defined(quarkVerbose):
  # Compiling with -d:quarkVerbose reports what this binary is being built
  # against: the configuration in use, the selected backend, and every setting
  # configure read back from how that backend was built.
  static: quarkReport(selectedBackend)

# switch should export absolutely everything that is exportable
when selectedBackend == "qex":
    quarkBackendFlags("qex")
    import qex/[qex]
    export qex
elif selectedBackend == "grid":
    quarkBackendFlags("grid")
    import grid/[grid]
    export grid
elif selectedBackend == "quda":
    quarkBackendFlags("quda")
    import quda/[quda]
    export quda
elif backend.len == 0:
    {.error: "no backend selected. Compile with -d:backend=grid, -d:backend=qex," &
             " or -d:backend=quda, or run ./configure to set a default.".}
else:
    {.error: "unsupported backend '" & backend & "'." &
             " Supported backends are grid, qex, and quda.".}
