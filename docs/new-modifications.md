# New Modifications and Clarifications

## Architecture-Specific, Not Target-Specific

We are now talking about **architecture-specific** code, not target-specific code.

We will have the following architecture-specific ports:

- `cortexm`
- `aarch32`
- `aarch64`
- `posix-arch`

The current SMP status is:

- `cortexm` is currently **not SMP**, but mus be SMP too
- All the other architectures are **SMP**.

## Repository Structure

Each architecture folder will be both:

1. A folder containing the architecture-specific source code.
2. A separate Git repository.

The build performed from each architecture repository will link the required sources from the main repository:

- `micro-os-plus-iii-smp`
- the `src` and `include` directories from the corresponding architecture repository.

In other words, the architecture repository contains the architecture-specific implementation, while the main `micro-os-plus-iii-smp` repository provides the common unified micro-os code.

## Existing `posix-arch` and `cortexm`

The existing:

- `posix-arch`

implementation have been moved into the workspace:

`micro-os-plus-iii-smp-old`

It now need to be **modified/updated to support SMP**.

### POSIX Native

For `posix-arch`, we also need to reconsider the current native POSIX SMP implementation.

The intended model is:

> Native host threads are the equivalent of CPUs.

Please analyze the current implementation and determine whether there is a better solution than the one currently used.

The goal is to have a clean and correct mapping between:

- micro-os SMP CPUs
- native POSIX host threads

without introducing unnecessary complexity.

## Unification Starting Point

The main conclusion is that each **port** — now meaning an **architecture-specific port** — should contain primarily the architecture-specific code:

```text
src/
include/
```

This code must integrate with and include the **common** part of the unified micro-os.

The common code is currently available in:

`micro-os-plus-iii-smp-old`

## Already Tested Implementations

Inside `micro-os-plus-iii-smp-old`, each project already contains the required patches and has been tested.

The existing tested projects include:

- `pico2`
- `rpi`
- `cortex-a7`
- `cortexm`

These tested folders are therefore the starting point for the unification, rpi will be  aarch64/aarch32, cortexm and pico2 in cortexm, cortex-a7 in aarch32, and posix-arch in posix-arch.

The unification should **start from these existing folders**, rather than recreating the implementations from scratch.

## Tests Must Also Be Migrated

The tests from the existing projects must also be brought into the new architecture.

In other words, the current tested projects in:

`micro-os-plus-iii-smp-old`

contain not only the patched implementation, but also the tests that prove that implementation works.

Those tests must be migrated into the corresponding projects/folders in the new:

`micro-os-plus-iii-smp`

structure.

The migration should preserve the existing tested behavior and use the existing projects as the reference implementations.

## Summary

The new structure should therefore follow these principles:

1. **Architecture-specific rather than target-specific** organization.
2. Four architecture repositories:
   - `cortexm`
   - `aarch32`
   - `aarch64`
   - `posix-arch`
3. `cortexm` must be updated to SMP.
4. `posix-arch` must be updated to SMP, with a review of the native POSIX CPU/thread mapping.
5. The common micro-os code remains in `micro-os-plus-iii-smp`.
6. The existing implementations in `micro-os-plus-iii-smp-old` are the reference starting point.
7. The already-tested projects:
   - `pico2`
   - `rpi`
   - `cortex-a7`
   - `cortexm`

   must be used as the basis for the unification.
8. Existing tests must be migrated together with the implementations into the new `micro-os-plus-iii-smp` structure.
9. No already-tested functionality should be lost during the restructuring.
