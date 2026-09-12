#[
Execution space conformance

src: quark/base/execution.nim
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

## Scoped execution placement and access lifetime
## ==============================================
##
## ``within Host`` and ``within Accelerator`` establish the Execution Context
## for placement-sensitive Quark operations. Each invocation introduces a new
## lexical scope. Whole-Field Assignments, Field View acquisition and access,
## and Parallel Site Loops require an explicit context; ordinary Nim statements
## inside the block retain their usual language semantics.
##
## Host selects host execution and host-accessible views. Accelerator selects
## the backend's accelerator execution and access facilities. An Accelerator
## context does not itself guarantee that a physical GPU is present. The backend
## must preserve the requested execution semantics or reject unsupported use.
## Placement and Site Granularity are independent: either context may operate
## on Scalar or Packed sites when that combination is supported.
##
## ``executionSpace()`` resolves the innermost context at the operation's call
## site. Nested contexts temporarily replace the outer placement, and leaving
## the inner block restores the outer one. Even nested blocks with the same
## placement have distinct scopes and access lifetimes. Context queries outside
## ``within`` reject instead of choosing an implicit default.
##
## A Field View's access lifetime ends with its owning declaration's scope and
## no later than the enclosing Execution Context. Normal exit, return, break,
## and exception unwinding close owned views exactly once. Copying a View or a
## Site Proxy copies an access handle, not permission to extend that lifetime.
## Using an escaped handle after closure must reject.
##
## The lifetime primitives in this module distinguish a scope, an owning handle,
## and a borrowed lease. Closing an already closed resource is harmless; closing
## a scope releases its remaining resources in reverse acquisition order.
## These primitives support the portable lifetime rule without prescribing
## native storage, memory transfer, or accelerator handle representation.
##
## The module establishes context and lifetime boundaries. The iteration module
## uses placement to select parallel lowering, and the Field interface attaches
## access modes and Lattice provenance to scoped access. Native acquisition,
## synchronization, execution, and release are supplied by the selected backend;
## conformance checks alone cannot establish their runtime behavior.


import std/[macros]

type ExecutionSpace* = enum
  Host = 0,       # CPU
  Accelerator = 1 # GPU or other accelerator unit

# Internal lifetime machinery. Adapters supply the close action; copied handles
# do not own it. The enclosing Execution Context is the final lifetime bound
type
  ViewLease* = ref object
    active: bool
    closeAction: proc() {.closure, raises: [].}
  ExecutionScope* = ref object
    active: bool
    leases: seq[ViewLease]
  ViewOwner* = object
    lease*: ViewLease
    owns: bool

proc close*(lease: ViewLease) {.raises: [].} =
  if lease != nil and lease.active:
    lease.active = false
    if lease.closeAction != nil: lease.closeAction()
    lease.closeAction = nil

proc `=destroy`*(owner: var ViewOwner) =
  if owner.owns: close(owner.lease)
  `=destroy`(owner.lease)

proc `=copy`*(destination: var ViewOwner; source: ViewOwner) =
  if destination.lease == source.lease: return
  if destination.owns: close(destination.lease)
  destination.lease = source.lease
  destination.owns = false

proc newExecutionScope*: ExecutionScope = ExecutionScope(active: true)

proc close*(scope: ExecutionScope) {.raises: [].} =
  if scope == nil or not scope.active: return
  scope.active = false
  for i in countdown(scope.leases.high, 0): close(scope.leases[i])
  scope.leases.setLen(0)

proc requireOpen*(lease: ViewLease) =
  if lease == nil or not lease.active:
    raise newException(ValueError, "Field View is outside its lifetime")

proc openView*(
  scope: ExecutionScope;
  closeAction: proc() {.closure, raises: [].} = nil
): ViewOwner =
  if scope == nil or not scope.active:
    raise newException(ValueError, "Execution Context is closed")
  let lease = ViewLease(active: true, closeAction: closeAction)
  scope.leases.add lease
  return ViewOwner(lease: lease, owns: true)

macro within*(space: ExecutionSpace, body: untyped): untyped =
  result = quote do:
    block:
      const quarkExecutionSpace {.inject, used.}: ExecutionSpace = `space`
      let quarkExecutionScope {.inject, used.} = newExecutionScope()
      defer: close(quarkExecutionScope)
      `body`

template executionSpace*(): ExecutionSpace =
  # Resolved at the operation call site, including nested within scopes.
  mixin quarkExecutionSpace
  when declared(quarkExecutionSpace):
    quarkExecutionSpace
  else:
    {.error: "operation requires within Host or within Accelerator".}

template executionScope*(): untyped =
  mixin quarkExecutionScope
  when declared(quarkExecutionScope): quarkExecutionScope
  else: {.error: "Field View requires within Host or within Accelerator".}

template fieldExecutionSpace*(): ExecutionSpace = executionSpace()

when isMainModule:
  import std/[unittest]

  suite "execution basics":
    test "within macro with Host execution space":
      var executed = false
      within Host: executed = true
      check executed

    test "within macro with Accelerator execution space":
      var executed = false
      within Accelerator: executed = true
      check executed

  suite "scope-owned close protocol":
    test "copies do not close; owners close once in reverse order":
      var events: seq[int]
      within Host:
        let first = openView(executionScope(), proc() {.raises: [].} = events.add 1)
        let second = openView(executionScope(), proc() {.raises: [].} = events.add 2)
        block:
          let copied = first
          requireOpen(copied.lease)
        requireOpen(first.lease)
        requireOpen(second.lease)
        check events.len == 0
      check events == @[2, 1]

    test "early return and exception unwinding close once":
      var closes = 0
      proc returning() =
        within Host:
          let owner = openView(executionScope(), proc() {.raises: [].} = inc closes)
          requireOpen(owner.lease)
          return
      returning()
      check closes == 1
      expect IOError:
        within Host:
          let owner = openView(executionScope(), proc() {.raises: [].} = inc closes)
          requireOpen(owner.lease)
          raise newException(IOError, "body failed")
      check closes == 2

    test "failed acquisition does not skip closing earlier resources":
      var closes = 0
      expect IOError:
        within Host:
          let owner = openView(executionScope(), proc() {.raises: [].} = inc closes)
          requireOpen(owner.lease)
          proc failOpen(): ViewOwner = raise newException(IOError, "open failed")
          let failed = failOpen()
          discard failed
      check closes == 1

    test "break closes its context":
      var closes = 0
      block stop:
        for i in 0 .. 1:
          within Host:
            let owner = openView(executionScope(), proc() {.raises: [].} = inc closes)
            requireOpen(owner.lease)
            break stop
      check closes == 1

  suite "execution context boundaries":
    test "context queries reject outside within":
      check not compiles(executionSpace())
      check not compiles(fieldExecutionSpace())
      check not compiles(executionScope())

    test "within introduces a fresh lexical scope":
      let local = 1
      within Host:
        let local = 2
        let onlyInside = 3
        check local == 2
        check onlyInside == 3
      check local == 1
      check not compiles(onlyInside)

    test "execution placement must be static":
      check not compiles(block:
        var placement = Host
        within placement: discard)

    test "nested placement restores the outer context":
      within Host:
        let outer = executionScope()
        check fieldExecutionSpace() == Host
        within Accelerator:
          check executionSpace() == Accelerator
          check fieldExecutionSpace() == Accelerator
          check executionScope() != outer
        check executionSpace() == Host
        check executionScope() == outer

    test "nested equal placements still have distinct lifetimes":
      var innerLease: ViewLease
      within Host:
        let outerOwner = openView(executionScope())
        within Host:
          let innerOwner = openView(executionScope())
          innerLease = innerOwner.lease
          requireOpen(outerOwner.lease)
          requireOpen(innerLease)
        expect ValueError: requireOpen(innerLease)
        requireOpen(outerOwner.lease)

    test "continue closes each iteration's views":
      var closes = 0
      for i in 0..<3:
        within Host:
          let owner = openView(executionScope(), proc() {.raises: [].} = inc closes)
          requireOpen(owner.lease)
          continue
      check closes == 3

    test "caught inner exception leaves outer views open":
      within Host:
        let outer = openView(executionScope())
        var innerLease: ViewLease
        expect IOError:
          within Accelerator:
            let inner = openView(executionScope())
            innerLease = inner.lease
            raise newException(IOError, "inner failed")
        expect ValueError: requireOpen(innerLease)
        requireOpen(outer.lease)
        check executionSpace() == Host

  suite "lease and owner edge cases":
    test "closing nil scopes and leases is harmless":
      close(ExecutionScope(nil))
      close(ViewLease(nil))
      expect ValueError: requireOpen(ViewLease(nil))

    test "an empty scope closes idempotently":
      let scope = newExecutionScope()
      close(scope)
      close(scope)
      expect ValueError: discard openView(scope)

    test "opening a nil context rejects":
      expect ValueError: discard openView(ExecutionScope(nil))

    test "a view needs no close callback":
      let scope = newExecutionScope()
      let owner = openView(scope)
      requireOpen(owner.lease)
      close(scope)
      expect ValueError: requireOpen(owner.lease)

    test "closing a lease is idempotent and leaves siblings open":
      var closes = 0
      let scope = newExecutionScope()
      let first = openView(scope, proc() {.raises: [].} = inc closes)
      let second = openView(scope, proc() {.raises: [].} = inc closes)
      close(first.lease)
      close(first.lease)
      expect ValueError: requireOpen(first.lease)
      requireOpen(second.lease)
      check closes == 1
      close(scope)
      close(scope)
      check closes == 2

    test "scope closure releases escaped owners in reverse acquisition order":
      var events: seq[int]
      var first, second: ViewOwner
      within Host:
        first = openView(executionScope(), proc() {.raises: [].} = events.add 1)
        second = openView(executionScope(), proc() {.raises: [].} = events.add 2)
      check events == @[2, 1]
      expect ValueError: requireOpen(first.lease)
      expect ValueError: requireOpen(second.lease)

    test "owner's narrower block bounds a borrowed lease":
      var borrowed: ViewLease
      var closes = 0
      within Host:
        block:
          let owner = openView(executionScope(), proc() {.raises: [].} = inc closes)
          borrowed = owner.lease
        check closes == 1
        expect ValueError: requireOpen(borrowed)
      check closes == 1

    test "copy assignment closes the previous owned lease":
      var closes = 0
      within Host:
        let source = openView(executionScope())
        var destination = openView(executionScope(), proc() {.raises: [].} = inc closes)
        let previous = destination.lease
        `=copy`(destination, source)
        check closes == 1
        expect ValueError: requireOpen(previous)
        requireOpen(source.lease)
        check destination.lease == source.lease
      check closes == 1

    test "self assignment preserves ownership":
      var closes = 0
      within Host:
        var owner = openView(executionScope(), proc() {.raises: [].} = inc closes)
        `=copy`(owner, owner)
        requireOpen(owner.lease)
        check closes == 0
      check closes == 1

    test "a close callback may close its own lease again":
      var closes = 0
      var lease: ViewLease
      within Host:
        let owner = openView(executionScope(), proc() {.raises: [].} =
          inc closes
          close(lease))
        lease = owner.lease
        close(lease)
        check closes == 1
      check closes == 1
