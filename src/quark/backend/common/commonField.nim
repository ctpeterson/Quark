#[
Temporary Field adapter scaffolding

src: quark/backend/common/commonField.nim
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

# Internal syntax scaffold shared until the native adapter slices replace it.
# Metadata operations work; storage operations reject explicitly at runtime.
import quark/base/[field, numeric, execution]

type
  ScaffoldSite*[T, S; M: static ViewMode] = object
    leaseData: ViewLease
  # A numeric computation result, with no Field association or write access.
  ScaffoldValue[T, S] = object
  ScaffoldOperand = ScaffoldSite | ScaffoldValue

proc newScaffoldSite*[T, S; M: static ViewMode](lease: ViewLease): ScaffoldSite[T, S, M] =
  ScaffoldSite[T, S, M](leaseData: lease)

template validateLease(value: untyped) =
  when value is ScaffoldSite: requireOpen(value.leaseData)

template siteType*[T, S, M](P: typedesc[ScaffoldSite[T, S, M]]): typedesc = T
template siteType*[T, S](V: typedesc[ScaffoldValue[T, S]]): typedesc = T
template indexType*[T, S, M](P: typedesc[ScaffoldSite[T, S, M]]): typedesc = S
template indexType*[T, S](V: typedesc[ScaffoldValue[T, S]]): typedesc = S
template mode*[T, S, M](site: ScaffoldSite[T, S, M]): ViewMode = M

template precision*[A: ScaffoldOperand](V: typedesc[A]): Precision = A.siteType.precision
template numericKind*[A: ScaffoldOperand](V: typedesc[A]): NumericKind = A.siteType.numericKind
template realType*[A: ScaffoldOperand](V: typedesc[A]): typedesc =
  ScaffoldValue[A.siteType.realType, A.indexType]

template requireReadable(A: typedesc) =
  when A is ScaffoldSite:
    when default(A).mode == WriteDiscard:
      {.error: "cannot read through a WriteDiscard view".}

template requireSameSites(A, B: typedesc) =
  when A.indexType isnot B.indexType:
    {.error: "site operands require the same index kind".}

# Operators validate their site operation's result type without evaluating it.
# Executing a placeholder operation always reports the missing implementation.
template defineUnary(symbol: untyped) =
  func symbol*[A: ScaffoldOperand](a: A): auto =
    mixin symbol
    requireReadable(A)
    type Result = typeof(symbol(default(A.siteType)))
    type Value = ScaffoldValue[Result, A.indexType]
    result = Value()
    validateLease(a)
    raise newException(ValueError, "Field site arithmetic is not implemented")

template defineBinary(symbol: untyped) =
  func symbol*[A, B: ScaffoldOperand](a: A; b: B): auto =
    mixin symbol
    requireReadable(A)
    requireReadable(B)
    requireSameSites(A, B)
    type Result = typeof(symbol(default(A.siteType), default(B.siteType)))
    type Value = ScaffoldValue[Result, A.indexType]
    result = Value()
    validateLease(a)
    validateLease(b)
    raise newException(ValueError, "Field site arithmetic is not implemented")

  func symbol*[A: ScaffoldOperand; B](a: A; b: B): auto =
    mixin symbol
    requireReadable(A)
    type Result = typeof(symbol(default(A.siteType), default(B)))
    type Value = ScaffoldValue[Result, A.indexType]
    result = Value()
    validateLease(a)
    validateLease(b)
    raise newException(ValueError, "Field site arithmetic is not implemented")

  func symbol*[A; B: ScaffoldOperand](a: A; b: B): auto =
    mixin symbol
    requireReadable(B)
    type Result = typeof(symbol(default(A), default(B.siteType)))
    type Value = ScaffoldValue[Result, B.indexType]
    result = Value()
    validateLease(a)
    validateLease(b)
    raise newException(ValueError, "Field site arithmetic is not implemented")

defineUnary(`+`)
defineUnary(`-`)
defineBinary(`+`)
defineBinary(`-`)
defineBinary(`*`)
defineBinary(`/`)
defineBinary(`div`)
defineBinary(`mod`)

func `==`*[T, S](a, b: ScaffoldValue[T, S]): bool =
  raise newException(ValueError, "Field site comparison is not implemented")

func `==`*[T, S, M](a, b: ScaffoldSite[T, S, M]): bool =
  requireReadable(typeof(a))
  validateLease(a)
  validateLease(b)
  raise newException(ValueError, "Field site comparison is not implemented")

func re*[A: ScaffoldOperand](a: A): A.realType =
  requireReadable(A)
  validateLease(a)
  raise newException(ValueError, "Field site reads are not implemented")

func im*[A: ScaffoldOperand](a: A): A.realType =
  requireReadable(A)
  validateLease(a)
  raise newException(ValueError, "Field site reads are not implemented")

proc `:=`*[T, S; M: static ViewMode; R](a: ScaffoldSite[T, S, M]; b: R) =
  when M == Read:
    {.error: "cannot assign through a Read view".}
  when R is ScaffoldOperand:
    requireReadable(R)
    requireSameSites(typeof(a), R)
    type Source = R.siteType
  else:
    type Source = R
  when not compiles(block:
    var value: T
    value = default(Source)
  ):
    {.error: "site assignment requires a compatible value".}
  validateLease(a)
  validateLease(b)
  raise newException(ValueError, "Field site assignment is not implemented")

proc `+=`*[T, S; M: static ViewMode; R: ScaffoldOperand](a: ScaffoldSite[T, S, M]; b: R) =
  when M != ReadWrite:
    {.error: "site addition requires a ReadWrite destination".}
  requireReadable(R)
  requireSameSites(typeof(a), R)
  when not compiles(block:
    var value: T
    value = default(T) + default(R.siteType)
  ):
    {.error: "site addition requires a compatible value".}
  validateLease(a)
  validateLease(b)
  raise newException(ValueError, "Field site addition is not implemented")

proc assignFieldScaffold*[F, R](destination: F; source: R; space: static ExecutionSpace) =
  # Only scalar initialization syntax is needed by Oracle A. No expression tree.
  mixin siteType
  when not compiles(block:
    var site: F.siteType
    site = source
  ):
    {.error: "Field initialization requires a value assignable to its site type".}
  raise newException(ValueError, "Field initialization is not implemented")
