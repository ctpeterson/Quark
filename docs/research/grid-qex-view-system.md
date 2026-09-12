# Grid views and a Grid-like view system for QEX

Research date: 2026-09-01

Status: source evidence and exploratory adapter-design proposals. The proposals are not accepted implementation requirements. Consult [ROADMAP.md](../../ROADMAP.md) for milestone scope; evaluate any proposed adapter-specific state or access machinery during the QEX integration milestone, using backend facilities. This report does not prescribe Milestone 1 work. The scope-owned close model was subsequently accepted in [ADR 0006](../adr/0006-bind-view-access-to-lexical-scopes.md) and exercised by the Milestone 1 lifetime scaffold; native coherence and synchronization proposals remain for backend integration.

## Scope and source snapshots

This report answers two questions:

1. What does Grid's view system actually do, including residency, freshness, lifetime, and scalar-versus-packed access?
2. What would Quark's QEX adapter need to own to provide the same useful behavior without inheriting Grid's weaker access-control and aliasing properties?

The evidence comes from primary source code at these unmodified local snapshots:

- Grid-HISQ commit [`1b0aa9899bec389f4c7afc57a4fe015b59aebec8`](https://github.com/ctpeterson/Grid-HISQ/tree/1b0aa9899bec389f4c7afc57a4fe015b59aebec8).
- QEX commit [`530d7829667a5d7a1924ee809177fb5ded64f0e9`](https://github.com/jcosborn/qex/tree/530d7829667a5d7a1924ee809177fb5ded64f0e9).
- Quark's current [domain vocabulary](../../CONTEXT.md) and [Oracle A](../../oracle/oracleA.nim).

Sections headed **Evidence** describe current source behavior. Sections headed **Design inference** propose Quark/QEX behavior.

## Executive conclusion

Grid's important idea is not the `LatticeView` pointer wrapper by itself. It is the scoped protocol around it:

```text
open(place, access)
  -> acquire a place-specific lease
  -> make that place current, copying only when preservation requires it
  -> return a trivially copyable kernel/loop handle
execute
close
  -> release the lease; do not eagerly copy to the other place
```

QEX already contains nearly all low-level pieces needed to implement this protocol: packed host fields, scalar-lane and packed device indexing, device allocation/copy primitives, `onGpu` capture hooks, CPU `threads` regions, and synchronous kernel finalization. What it does not currently have is a durable, per-storage coherence owner with scoped access leases.

The recommended adapter therefore owns one control block per Quark Field storage allocation. The control block owns the QEX host Field, a lazy device allocation, freshness state, active-view claims, and device lifetime. A host or accelerator Field View is a short-lived typed lease over that control block. It exposes only a small host or device access handle to the loop. It should not implement correctness by mutating QEX's current `CpuGpu`/`GpuMem` intent flags.

This also clarifies iteration: QEX's current `gpuSites` deliberately chooses scalar `SiteV[1]` on a real GPU and packed `SiteV[V]` on its CPU backend. Quark must instead lower its two explicit iteration spaces separately. Accelerator Scalar Sites use scalar-lane indexing; Accelerator Packed Sites use outer-site indexing with `SiteV[V]`, even on a GPU.

## Grid's view system

### Evidence: the owning lattice and the access handle are separate

`Lattice<vobj>` owns an outer-site allocation and host-only grid metadata. `LatticeAccelerator<vobj>` contains the smaller device-usable subset: grid pointer, checkerboard, outer-site pointer and size, and advice. `LatticeView<vobj>` derives from that device-usable subset and adds the access mode plus the original CPU pointer used to close the view ([`Lattice_view.h` lines 16-40 and 51-105](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_view.h#L16-L105)).

The lattice's `View(mode)` constructs a `LatticeView`, which calls `MemoryManager::ViewOpen`. That call may replace the lattice's host pointer in the view with a device pointer. Closing passes the original CPU pointer and mode back to the manager ([`Lattice_base.h` lines 98-108](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_base.h#L98-L108), [`Lattice_view.h` lines 83-106](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_view.h#L83-L106)). The returned view is intentionally trivially copyable so it can be captured by a device lambda ([`Lattice_view.h` lines 51-55 and 83-85](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_view.h#L51-L85)).

### Evidence: modes describe placement and preservation

Grid defines `AcceleratorRead`, `AcceleratorWrite`, `AcceleratorWriteDiscard`, `CpuRead`, and `CpuWrite`; `CpuWriteDiscard` is currently only an alias for `CpuWrite` ([`MemoryManager.h` lines 62-72](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManager.h#L62-L72)). In actual transitions:

- accelerator read preserves existing contents and clones host-to-device when the host is newer;
- accelerator write also preserves existing contents, then declares the accelerator copy authoritative;
- accelerator write-discard allocates a device copy when necessary but skips host-to-device cloning;
- CPU read flushes device-to-host when the device is newer;
- CPU write also flushes first when the device is newer, then declares the CPU copy authoritative.

These are not merely names: the transition table and code implement them ([`MemoryManagerCache.cc` lines 281-355](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L281-L355), [`MemoryManagerCache.cc` lines 387-454](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L387-L454)).

Grid's mode is a coherence contract, not a C++ permission type. `LatticeView::operator[]` returns a mutable reference even from a `const` view, so `AcceleratorRead` does not itself make writes ill-typed ([`Lattice_view.h` lines 60-77](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_view.h#L60-L77)). Quark must add its own compile-time `Read`/`ReadWrite`/`WriteDiscard` enforcement.

### Evidence: freshness is a three-state cache protocol

For non-unified memory, the manager indexes an `AcceleratorViewEntry` by CPU address. Each entry records CPU and accelerator pointers, byte size, one freshness state, CPU and accelerator lock counts, and LRU information ([`MemoryManager.h` lines 160-180](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManager.h#L160-L180)). Its substantive states are:

- `CpuDirty`: the CPU copy is authoritative and a device allocation may not exist;
- `Consistent`: both copies are current;
- `AccDirty`: the accelerator copy is authoritative.

The definitions are explicit in [`MemoryManagerCache.cc` lines 33-44](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L33-L44). `Clone` allocates if needed and copies host-to-device, while `Flush` copies device-to-host; both end in `Consistent` ([`MemoryManagerCache.cc` lines 163-205](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L163-L205)).

Opening a writing view changes freshness immediately. Closing a view only decrements its lock count and, for an unlocked device entry, makes it eligible for LRU eviction. It does **not** copy data to the other place ([`MemoryManagerCache.cc` lines 360-385](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L360-L385)). A later view at the other place triggers the needed copy. Eviction similarly flushes only an authoritative device copy before freeing it ([`MemoryManagerCache.cc` lines 129-175](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L129-L175)).

Under `GRID_UVM`, `ViewOpen` simply returns the original pointer and `ViewClose` is empty, so the explicit cache protocol is bypassed in favor of shared/unified allocation behavior ([`MemoryManagerShared.cc` lines 1-20](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerShared.cc#L1-L20)).

### Evidence: scope closes the lease, while loop completion orders use

`autoView` creates the view and a `ViewCloser`; the closer stores a copy and invokes `ViewClose` in its destructor ([`Lattice_view.h` lines 110-163](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_view.h#L110-L163)). Copies captured by accelerator lambdas are just handles; they do not independently close the lease.

Grid's blocking `accelerator_for` expands to a nonblocking launch followed by an accelerator barrier ([`Accelerator.h` lines 566-579](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/threads/Accelerator.h#L566-L579)). Thus the normal pattern closes only after device work has completed. Any nonblocking use must keep the view open until the corresponding work is complete; the RAII scope alone cannot make an early close safe.

### Evidence: outer-site storage supports either scalar SIMT or packed access

On a host, `coalescedRead` and `coalescedWrite` are whole-vector operations. Under `GRID_SIMT`, they extract or insert the lane selected by `acceleratorSIMTlane` and return a scalar object ([`Tensor_SIMT.h` lines 56-95 and 98-195](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/tensors/Tensor_SIMT.h#L56-L195)).

The `nsimd` argument to `accelerator_for` creates a device launch dimension of that size, with the lane mapped to `threadIdx.x` on CUDA ([`Accelerator.h` lines 114-120 and 135-179](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/threads/Accelerator.h#L114-L179)). Consequently:

- `accelerator_for(ss, oSites, vobj::Nsimd(), ...)` plus `coalescedRead/Write` processes one scalar lane per SIMT lane;
- `accelerator_for(ss, oSites, 1, ...)` plus direct `view[ss]` access processes one complete packed object per outer site.

Grid uses the first form pervasively in lattice arithmetic ([`Lattice_base.h` lines 131-139](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_base.h#L131-L139)) and demonstrates the second explicitly in `outerProduct` ([`Lattice_local.h` lines 68-84](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/lattice/Lattice_local.h#L68-L84)). On a CPU-only Grid build, `accelerator_for` falls back to `thread_for`, which is an OpenMP parallel-for over outer sites ([`Accelerator.h` lines 585-615](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/threads/Accelerator.h#L585-L615), [`Threads.h` lines 48-70](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/threads/Threads.h#L48-L70)).

### Evidence: Grid's safety boundary is narrower than Quark's

Grid rejects simultaneous CPU and accelerator views with assertions: accelerator open requires `cpuLock == 0`, and CPU open requires `accLock == 0` ([`MemoryManagerCache.cc` lines 253-270 and 399-417](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L253-L270)). It increments lock counts for multiple views at the same place, however, without distinguishing readers from writers ([`MemoryManagerCache.cc` lines 313-339 and 431-447](https://github.com/ctpeterson/Grid-HISQ/blob/1b0aa9899bec389f4c7afc57a4fe015b59aebec8/Grid/allocator/MemoryManagerCache.cc#L313-L339)). The source shown also contains no synchronization around the global view table and LRU. Therefore Grid's manager detects cross-place misuse but does not provide a general concurrent-reader/exclusive-writer discipline.

The write-discard promise is also not checked for complete coverage, and CPU write-discard is not optimized separately. Those are gaps Quark need not copy.

## QEX's current CPU and accelerator structure

### Evidence: CPU Fields are packed outer-site allocations

A QEX `Field[V,T]` is a reference to a `FieldObj` containing an `alignedMem[T]`, `Layout[V]`, and element size. Construction allocates `l.nSitesOuter` elements ([`fieldET.nim` lines 17-25 and 118-139](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/field/fieldET.nim#L17-L139)). `alignedMem` owns a reference-counted raw allocation, aligns its typed data pointer, and provides direct unchecked indexing ([`alignedMem.nim` lines 5-21, 53-68, and 77-119](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/base/alignedMem.nim#L5-L119)).

The layout records both scalar local volume (`nSites`) and packed outer volume (`nSitesOuter`), with `nSitesInner = nSites / nSitesOuter` ([`layoutTypes.nim` lines 87-120](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/layout/layoutTypes.nim#L87-L120), [`qlayout.nim` lines 52-61](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/layout/qlayout.nim#L52-L61)). Ordinary `field[i]` indexes an outer packed element ([`fieldET.nim` lines 236-241](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/field/fieldET.nim#L236-L241)). Scalar access computes outer index and SIMD lane and indexes the lane through `asSimd` ([`fieldET.nim` lines 457-483](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/field/fieldET.nim#L457-L483)).

QEX's CPU iteration likewise distinguishes `items` (outer sites) from `sites` (scalar sites). Work is partitioned using thread-local `threadNum`/`numThreads`; scalar partitions are aligned to the SIMD width ([`fieldET.nim` lines 363-443](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/field/fieldET.nim#L363-L443)). A `threads` scope creates an OpenMP parallel region, initializes per-thread identity, and brackets the body with barriers ([`threading.nim` lines 80-110](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/base/threading.nim#L80-L110)).

### Evidence: GPU Fields are small descriptors over a separately managed pointer

`GpuFieldObj[V,T]` holds the outer-site count, a typed device pointer, and a pointer to a `GpuMem` record. Its indexing overloads are already the right primitives for Quark's two Site Index kinds:

- `SiteV[1]` divides by `V`, selects a lane, and produces scalar access;
- `SiteV[V]` directly indexes one packed outer element.

See [`cgfield.nim` lines 5-50](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cgfield.nim#L5-L50). QEX maps CPU SIMD-containing element types to GPU-side representation types with `gpuType`, and maps a CPU Field to a `GpuField` ([`accel.nim` lines 174-185](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/accel.nim#L174-L185)). The existing Field transfer path raw-copies `nSitesOuter * sizeof(gpu element)` bytes between the host allocation and its device allocation ([`cgfield.nim` lines 89-119](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cgfield.nim#L89-L119)).

### Evidence: native GPU iteration currently chooses scalar lanes

`SiteV` carries its lane-group width as a static parameter. On a real accelerator backend, `gpuSites(n,V)` iterates `n*V` scalar positions and yields `SiteV[1]`; on the CPU backend it iterates `n` outer positions and yields `SiteV[V]` ([`accel.nim` lines 146-172](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/accel.nim#L146-L172)). `gpuRange` is a grid-stride loop on GPU and a balanced thread partition on CPU ([`accel.nim` lines 146-159](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/accel.nim#L146-L159)).

This is an efficient default for QEX operations, but it cannot represent both Quark iteration spaces by itself. Quark's index kind, not the compilation target, decides whether access is scalar or packed.

### Evidence: `onGpu` discovers captures and brackets a kernel with transfer hooks

The CUDA `onGpuNowait` macro discovers variables captured by the body, calls `toGpu` to construct its kernel-argument tuple, rewrites body accesses through `getGpu`, launches a kernel, and returns a finalizer. The finalizer synchronizes the device and calls `fromGpu` for each captured value ([`cudabe.nim` lines 97-164](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cudabe.nim#L97-L164)). The blocking `onGpu` forms immediately invoke that finalizer ([`cudabe.nim` lines 180-204](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cudabe.nim#L180-L204)). The CPU backend follows the same capture/prepare/finalize shape but executes the body through QEX threads ([`cpu.nim` lines 19-90 and 106-130](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cpu.nim#L19-L130)).

This hook protocol is a valuable seam: a Quark accelerator view can define `toGpu/getGpu/fromGpu` so kernel capture passes through its already-prepared device descriptor, with no additional coherence decision inside `onGpu`.

### Evidence: QEX has two existing transfer/freshness mechanisms

`CpuGpu[C,G]` stores both representations plus four booleans describing anticipated reads and writes, use/copy counters, and copy-in/copy-out positions. Before a kernel it copies in when the GPU may read and the CPU may have written; afterward it copies out when the CPU may read and the GPU may have written ([`cpugpu.nim` lines 3-16 and 27-91](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cpugpu.nim#L3-L91)).

Separately, `GpuMem` is a global table entry keyed by host pointer. Its flags describe possible CPU/GPU reads and writes, while kernel-number counters suppress duplicate transfers within one kernel. The default enables CPU read/write and GPU read/write, so default use is conservative; specialized code mutates flags to suppress transfers ([`gpumem.nim` lines 15-38 and 75-118](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/gpumem.nim#L15-L118)). `getGpuMem` lazily creates the table entry and device allocation and asserts that later requests through the same host address use the same byte size ([`gpumem.nim` lines 125-181](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/gpumem.nim#L125-L181)).

`CgField` combines the two: it is a `CpuGpu` wrapper whose GPU half points at a `GpuMem` allocation. Its custom finalizer removes that `GpuMem` entry; a plain QEX `Field` transferred through `toGpu` has no corresponding Field finalizer in this code ([`cgfield.nim` lines 170-217](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cgfield.nim#L170-L217), [`alignedMem.nim` lines 53-68](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/base/alignedMem.nim#L53-L68)).

### Evidence and inference: limitations of the current mechanisms

The following are important when deciding whether to build views directly from `CpuGpu`/`GpuMem`:

1. **Intent and freshness are conflated.** `noReadCpu`, `noWriteCpu`, and their GPU counterparts determine whether a transfer occurs; there is no independent `HostLatest`/`DeviceLatest` state. Direct CPU Field access does not report a mutation to these objects. Correct optimized use therefore depends on manually maintaining prospective-use flags around every access ([`cpugpu.nim` lines 27-78](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cpugpu.nim#L27-L78)). This is evidence; the conclusion that it is too fragile for Quark views is design inference.
2. **The global cache is keyed by an address, not an owning storage identity.** It detects a byte-size mismatch, but it does not record overlapping ranges or aliases ([`gpumem.nim` lines 125-181](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/gpumem.nim#L125-L181)). Two wrappers over the same storage can also carry independent `CpuGpu` flags. Therefore aliasing can produce incompatible coherence decisions.
3. **Lifetime is asymmetric.** `alignedMem` frees host memory through its own reference-counted `RawMemRef`; the plain Field-to-GPU path puts a device allocation in the global table, but only `CgField` explicitly removes an entry in its finalizer ([`alignedMem.nim` lines 53-68](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/base/alignedMem.nim#L53-L68), [`cgfield.nim` lines 182-217](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cgfield.nim#L182-L217)). Address reuse and multiple `CgField` wrappers over one host Field are consequently hazardous unless ownership is externally constrained.
4. **There are no active-view claims.** Neither mechanism prevents host access while a device use is outstanding, conflicting writers, or a device allocation being freed through another alias. `onGpuNowait` makes the ordering issue concrete because work remains live until its returned finalizer is called ([`cudabe.nim` lines 109-164](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cudabe.nim#L109-L164)).
5. **The manager structures shown are process-global and unsynchronized.** QEX's GPU-memory table operations contain no locking, while QEX CPU execution commonly occurs inside OpenMP regions ([`gpumem.nim` lines 125-202](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/gpumem.nim#L125-L202), [`threading.nim` lines 80-110](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/base/threading.nim#L80-L110)). Calls happen safely only if the surrounding program serializes management operations; this is an inference from the absence of synchronization, not a claim about every caller.
6. **Pointers into the global table deserve special caution.** `GpuFieldObj` retains a `ptr GpuMem`, and the table can grow as other allocations are inserted ([`cgfield.nim` lines 8-14](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cgfield.nim#L8-L14), [`gpumem.nim` lines 141-173](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/gpumem.nim#L141-L173)). Whether Nim's particular table implementation preserves such element addresses must be established before treating that pointer as durable.

## Proposed Quark/QEX view architecture

Everything in this section is **design inference** unless it explicitly cites existing behavior.

### 1. Put coherence in one storage control block

Each Quark QEX Field should contain or reference a control block conceptually like:

```nim
type QexFieldStorage[V: static int, HostElem, DeviceElem] = ref object
  host: qex.Field[V, HostElem]
  device: ptr UncheckedArray[DeviceElem] # lazy
  outerSites: int
  bytes: int
  freshness: Freshness                  # Uninitialized, HostLatest, BothLatest, DeviceLatest, Invalid
  activePlace: Option[Place]             # none, Host, Accelerator
  readers: int
  writer: bool
  generation: uint64
```

The control block, not a raw host address and not an individual wrapper, is the storage identity. Copies of the Quark Field share it. It owns and eventually frees the device allocation. The underlying QEX Field remains private so portable code cannot mutate host storage without opening a Quark view.

For the first vertical slice, allocate/free with QEX's exported accelerator primitives and store the device pointer directly. Do not route correctness through the existing global `GpuMem` table. A later QEX-level improvement could replace this with a coherent cache/eviction manager, but only if that manager accepts stable storage identities and explicit view transitions.

### 2. Treat a view as an access lease, not as the coherence owner

A view should carry:

- a reference that keeps the control block alive for the scope;
- a small place-specific data handle (`qex.Field`/host pointer or `GpuField`-shaped device descriptor);
- static place and access parameters used to expose only legal operations;
- one close token so copies captured by loops do not close independently.

The public types can erase those extra parameters behind Oracle A's `FieldView[Complex]` spelling, but the elaborated type must distinguish `Read`, `ReadWrite`, and `WriteDiscard`. A `Read` view supplies only reads. `WriteDiscard` supplies writes but no reads or read-modify-write operators. `ReadWrite` supplies both.

Unlike Grid, Quark should use same-place shared-reader/exclusive-writer claims. Allow multiple read leases at one place. Reject any writer overlapping another lease, and reject all cross-place overlap. This catches aliases rather than merely counting them.

### 3. Use explicit freshness transitions

Opening and successfully closing a view should follow this table:

| Place | Mode | Open action | Successful close |
|---|---|---|---|
| Host | `Read` | If `DeviceLatest`, synchronize then copy device to host | freshness unchanged after any required sync (`BothLatest`) |
| Host | `ReadWrite` | If `DeviceLatest`, synchronize then copy device to host | `HostLatest` |
| Host | `WriteDiscard` | No preservation copy; make old values unavailable | `HostLatest` |
| Accelerator | `Read` | If `HostLatest`, allocate if needed and copy host to device | freshness unchanged after any required sync (`BothLatest`) |
| Accelerator | `ReadWrite` | If `HostLatest`, allocate/copy host to device | `DeviceLatest` |
| Accelerator | `WriteDiscard` | Allocate if needed; no host-to-device copy | `DeviceLatest` |

Writer freshness should be committed at successful close, not at open. During a writer lease, record an in-progress state so no other view can observe either copy. If execution fails, mark a WriteDiscard result `Invalid`; for ReadWrite, either mark invalid or retain the old authoritative copy only when the adapter can prove no partial writes reached it.

Close should not copy to the other place. This preserves Grid's useful lazy behavior and Oracle A's statement that later views synchronize as required.

### 4. Make scope lowering responsible for exactly one close

The Execution Context macro knows the place; the `view` call knows the access mode. Lower the enclosing scope with `defer`/`try-finally`-equivalent cleanup so each opened lease closes on every normal Nim control-flow exit. Copies placed in a CPU loop body or device kernel carry only data handles.

For blocking QEX `onGpu`, close after `onGpu` returns, because its finalizer has synchronized the device ([`cudabe.nim` lines 135-164 and 194-204](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cudabe.nim#L135-L204)). If Quark later exposes nonblocking execution, the lease must move into the returned completion object and close only when its finalizer/event completes.

Open/close and transfer-state mutation should run once outside QEX's `threads` body, or under `threadSingle` with surrounding barriers. The host data handle can then be copied into the parallel region. This avoids making the control block itself a contended per-site object.

### 5. Make QEX kernel capture a pass-through for prepared views

An accelerator view can reuse `GpuField`'s `n`/`p` access shape without using its `pgm` pointer. Define its QEX capture hooks approximately as:

```nim
proc toGpu(v: AcceleratorView): DeviceView = v.preparedDeviceHandle
template getGpu(v: AcceleratorView, d: DeviceView): untyped = d
template fromGpu(v: AcceleratorView, d: DeviceView) = discard
```

All preservation copies already occurred at view-open, and freshness is committed at view-close. This stops `onGpu` from making a second, flag-based coherence decision. It also keeps the device kernel argument trivially copyable in the same spirit as Grid's `LatticeView`.

### 6. Lower the four place/iteration combinations explicitly

Do not directly equate Quark `lattice.sites(Packed)` with QEX's current `gpuSites`, because the latter changes index kind by backend target. The adapter should select extent, `SiteV` kind, and access operation together:

| Quark loop | QEX lowering | Field access result |
|---|---|---|
| Host + Scalar Sites | `threads:` plus an ordinary loop over `0 ..< nSites`, partitioned/aligned as QEX does for `sites` | scalar lane |
| Host + Packed Sites | `threads:` plus an ordinary loop over `0 ..< nSitesOuter`, partitioned as QEX does for `items` | packed element |
| Accelerator + Scalar Sites | `onGpu` with a grid-stride loop over `nSitesOuter * V`, yielding `SiteV[1]` | scalar lane |
| Accelerator + Packed Sites | `onGpu` with a grid-stride loop over `nSitesOuter`, yielding `SiteV[V]` | packed element |

On QEX's CPU accelerator backend, preserve the same Quark distinction: Scalar remains scalar and Packed remains packed. `backendIsGpu` must not silently change the portable Site Index kind. QEX's existing `GpuField` overloads already demonstrate both access forms ([`cgfield.nim` lines 31-50](https://github.com/jcosborn/qex/blob/530d7829667a5d7a1924ee809177fb5ded64f0e9/src/backend/cgfield.nim#L31-L50)); the new work is selecting them explicitly.

### 7. Define failure behavior up front

The adapter should reject rather than guess in these cases:

- reading an uninitialized or invalid Field;
- reading through `WriteDiscard` or writing through `Read` (compile-time when possible);
- cross-place overlapping leases;
- any writer overlapping another lease, including through aliases;
- closing a view before its asynchronous work completes;
- a host/device element-size or layout mismatch;
- device allocation/copy failure;
- destruction while a lease or asynchronous use is active.

WriteDiscard's “every element is assigned” rule is stronger than a normal write-only type. Oracle A's full-domain parallel loops make coverage observable, but arbitrary future code may not. Initially treat complete coverage as a checked contract at Quark lowering boundaries where the full iteration domain is known; otherwise reject unsupported partial-region WriteDiscard or add a debug coverage mechanism rather than silently weakening the rule.

### 8. Test the protocol, not only the result

Focused QEX-adapter tests should cover:

- host write -> accelerator read causes exactly one host-to-device copy;
- accelerator write -> subsequent accelerator read causes no device-to-host copy;
- accelerator write -> host read copies back at the later host open, not at accelerator close;
- accelerator WriteDiscard skips host-to-device copy;
- ReadWrite preserves old contents; WriteDiscard does not expose them;
- repeated same-place reads share safely; read/write and cross-place aliases reject;
- copied Field wrappers share freshness and device ownership;
- Scalar and Packed loops generate `SiteV[1]` and `SiteV[V]` respectively on both GPU and CPU backend builds;
- the accelerator-view `toGpu/getGpu/fromGpu` hooks do not invoke `GpuMem.copyIn/copyOut`;
- normal and exceptional scope exits close exactly once;
- generated CUDA/HIP/SYCL or expanded Nim retains QEX's native `onGpu`/grid-stride structure.

## Recommended implementation boundary

For Oracle A, the smallest coherent vertical slice is:

1. Quark's QEX Field wrapper privately owns a QEX host Field through a shared control block.
2. The control block owns a lazy device pointer and the explicit freshness/lease state machine.
3. Quark views elaborate to access- and place-qualified QEX adapter handles.
4. Accelerator handles pass through QEX `onGpu` capture without QEX's flag-driven copies.
5. Quark lowers Scalar and Packed iteration independently using QEX's native thread and accelerator primitives.
6. Whole-Field Assignment uses the same view protocol, normally Accelerator `WriteDiscard`, rather than a separate coherence path.

This reproduces the deep part of Grid's design—scoped access and lazy dual-residency coherence—while improving the properties Quark explicitly requires: typed permissions, stable ownership, alias-aware rejection, deterministic index kinds, and inspectable lowering.
