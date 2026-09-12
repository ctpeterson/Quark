# Lifecycle oracle for Milestone 2 Step 1, compiled once per exit path:
# -d:oracleExit=normal, -d:oracleExit=return, -d:oracleExit=raise
# Each process enters quark exactly once; no backend reinitialization is assumed.
# Native acceptance additionally traces one backend initialize/finalize pair,
# with body cleanup preceding finalization. Passing this source alone proves
# language-level control flow, not that native runtime calls have been connected.

import quark

const oracleExit {.strdefine.} = "normal"
static: doAssert oracleExit in ["normal", "return", "raise"]
var events: seq[string]

proc program() =
  quark:
    events.add "body"
    defer: events.add "cleanup"
    when oracleExit == "return": return
    elif oracleExit == "raise": raise newException(IOError, "oracle lifecycle exit")
    else: events.add "end"

var caught = false
try: program()
except IOError: caught = true
when oracleExit == "normal":
  doAssert not caught
  doAssert events == @["body", "end", "cleanup"]
elif oracleExit == "return":
  doAssert not caught
  doAssert events == @["body", "cleanup"]
else:
  doAssert caught
  doAssert events == @["body", "cleanup"]
