#[
Show configuration

src: quark/build/showConfig.nim
Author: Curtis Taylor Peterson <curtistaylorpetersonwork@gmail.com>

Reports the Quark build configuration the compiler resolved, which is the
first thing to check when an installed Quark does not find a backend. Because
the configuration is resolved at compile time, this program has to be
recompiled to report a change; that is the point, since it then reports
exactly what any other Quark build on this machine would see.

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

import ./configuration

# The report is built during compilation, because that is when the
# configuration is resolved, and printed at run time. It is the same account
# that '-d:quarkVerbose' prints while compiling any Quark program.
const report = quarkReportLines()

when isMainModule:
  for line in report:
    echo line
