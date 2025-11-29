# Roadmap

This document tracks the development progress of C3nif.

## Phase 1: Core Foundation (Completed)

### C3 Runtime Library (`c3nif.c3l/`)
- [x] FFI Bindings (`erl_nif.c3`)
  - [x] Complete FFI bindings to erl_nif.h
  - [x] Type definitions (ErlNifTerm, ErlNifEnv, ErlNifEntry, ErlNifFunc)
  - [x] Function pointer types for NIF callbacks
  - [x] External function declarations for all core erl_nif.h functions
  - [x] Character encoding enums
  - [x] Resource type structures
- [x] Environment wrapper (`env.c3`)
  - [x] `Env` struct for process-bound environments
  - [x] `OwnedEnv` struct for process-independent environments
  - [x] Fault definitions (NO_PROCESS, ALLOC_FAILED)
  - [x] Environment lifecycle functions (wrap, raw, priv_data, self)
  - [x] Message sending (send)
  - [x] Timeslice management (consume_timeslice)
- [x] Term wrapper (`term.c3`)
  - [x] `Term` struct wrapping ErlNifTerm
  - [x] Type checking functions (is_atom, is_binary, is_list, etc.)
  - [x] Integer operations (make_int, make_uint, make_long, get_int, etc.)
  - [x] Float operations (make_double, get_double)
  - [x] Atom operations (make_atom, make_existing_atom)
  - [x] Binary operations (inspect_binary, make_new_binary, make_sub_binary)
  - [x] String operations (make_string, make_string_len)
  - [x] List operations (make_empty_list, make_list_cell, get_list_cell, etc.)
  - [x] Tuple operations (make_tuple_from_array, get_tuple)
  - [x] Map operations (make_new_map, map_put, map_get, get_map_size)
  - [x] Reference operations (make_ref)
  - [x] Error handling (make_badarg, raise_exception)
  - [x] PID operations (get_local_pid)
  - [x] Operator overloading for comparison (`==` via `equals`, `compare_to`)
- [x] Main module facade (`c3nif.c3`)
  - [x] Type aliases for convenience
  - [x] NIF entry helper (make_nif_entry)
  - [x] Version information

### Mix Integration (`lib/`)
- [x] Main module (`c3nif.ex`)
  - [x] `use C3nif` macro with `:otp_app` option
  - [x] `~c3` sigil for inline C3 code
  - [x] Code accumulation via module attributes
  - [x] NIF extension detection per platform
- [x] Compiler module (`c3nif/compiler.ex`)
  - [x] `@before_compile` hook for compilation
  - [x] Staging directory management
  - [x] Project.json generation for c3c
  - [x] Library symlinking (c3nif.c3l)
  - [x] c3c invocation and error handling
  - [x] NIF loading via `@on_load` callback

### Test Infrastructure
- [x] Test helper setup (`test/test_helper.exs`)
- [x] Test case module (`test/support/c3nif_case.ex`)
  - [x] c3c availability check
  - [x] `compile_test_nif/3` helper
  - [x] Temporary directory management
- [x] Basic tests (`test/c3nif_test.exs`)
- [x] Compiler integration tests (`test/c3nif/compiler_test.exs`)

### Known Limitations
- [ ] ASan with dynamic libraries (C3 uses lld directly, not cc for dynamic lib linking)
  - Workaround: Use Valgrind or LD_PRELOAD for leak detection

## Phase 2: Advanced Runtime Features

### Binary Handling
- [x] `c3nif.c3l/binary.c3` - Binary handling
  - [x] Zero-copy binary inspection (`inspect`, `inspect_iolist`)
  - [x] Reference-counted binary handling (`alloc`, `release`, `realloc`)
  - [ ] enif_keep_binary (skipped for now, rarely needed)
  - [x] Sub-binary creation (`make_sub`)
  - [x] Heap vs refc binary threshold (64 bytes) - documented
  - [x] Ownership semantics (borrowed vs owned)
  - [x] C3 slice integration (`as_slice`, `as_mut_slice`)
  - [x] Convenience helpers (`from_slice`, `copy`)

### Resource Management
- [x] `resource.c3` - Full resource management
  - [x] Resource type registration
  - [x] Destructor callbacks
  - [x] Down callbacks (process monitoring)
  - [x] Thread-safety documentation

### Allocator Integration
- [x] `allocator.c3` - BEAM allocator wrappers
  - [x] BeamAllocator struct implementing C3 Allocator interface
  - [x] Convenience functions (`alloc`, `calloc`, `realloc`, `free`)
  - [x] Aligned allocation support for SIMD operations
  - [x] Thread-safety documentation
  - [x] VM memory tracking (visible in `erlang:memory()`)
  - [x] Strict allocator pairing documentation

### Safety Hardening
- [x] `safety.c3` - Error isolation
  - [x] NIF-specific faults (ALLOC_FAILED, RESOURCE_ERROR, ENCODE_ERROR, ARGC_MISMATCH)
  - [x] NifResult type for explicit error handling
  - [x] Argument validation helpers (get_arg, require_int, require_long, etc.)
  - [x] Range validation (require_int_range, require_non_negative, require_positive)
  - [x] Type validation (require_atom, require_binary, require_list, require_tuple, require_map, require_pid)
  - [x] Fault-to-error helpers (make_badarg_error, make_overflow_error, etc.)
  - [x] Two-layer NIF pattern documentation (inner uses optionals, outer catches faults)
  - [x] Re-exports in c3nif.c3 for convenience

## Phase 3: Scheduler Support

### Timeslice Management
- [x] `enif_consume_timeslice` high-level wrapper (`Env.consume_timeslice`)
- [x] Yielding NIF support (`enif_schedule_nif`)
  - [x] `schedule_nif` high-level wrapper
  - [x] `schedule_dirty_cpu`, `schedule_dirty_io`, `schedule_normal` convenience functions
- [ ] Execution time profiling utilities

### Dirty Schedulers
- [x] FFI bindings for dirty scheduler flags
- [x] Thread type detection (`current_thread_type`, `is_dirty_scheduler`, `is_normal_scheduler`)
- [x] Process liveness check (`is_process_alive`) for dirty scheduler cleanup
- [x] `scheduler.c3` module with all scheduler operations
- [x] Static dirty scheduler declaration via `ErlNifFunc.flags`
- [x] Dynamic scheduling between normal/dirty schedulers
- [x] High-level dirty scheduler integration via annotations (`<* nif: dirty = cpu *>`)
- [x] Documentation of dirty scheduler limitations (in scheduler.c3 module docs)
  - [x] Which enif_* functions are safe (all term/memory ops work)
  - [x] Process termination behavior (NIF continues, check `is_process_alive`)
  - [x] GC delays during dirty NIF execution

## Phase 4: Code Generation

### Implemented
- [x] Parse C3 source for `nif:` annotations in doc comments
  - Uses `<* nif: arity = N *>` format to avoid C3 contract syntax conflicts
  - Supports: `arity`, `name` (custom Elixir name), `dirty` (cpu/io)
- [x] Generate `ErlNifEntry` struct automatically
  - Generates `__c3nif_funcs__` array with function metadata
  - Generates `nif_init()` function with proper `@export` attribute
- [x] Auto-detect `on_load`/`on_unload` callbacks by function name and signature
- [x] Automatic NIF function collection via Elixir-side parsing

### Not Implemented (Future Work)
- [ ] Generate Elixir function stubs (users write manual stubs - Rustler style)
- [ ] Dialyzer typespec generation
- [ ] Resource type name prefixing (avoid conflicts)

## Phase 5: Enhanced Mix Integration

- [x] Mix compiler task (`mix compile.c3nif`)
- [ ] Artifact copying to `priv/native/`
- [ ] `mix c3nif.new` project generator
- [ ] Recompilation detection via `@external_resource`
- [ ] Configuration system
  - [ ] debug/release modes
  - [ ] C3 compiler path selection
  - [ ] Custom environment variables
  - [ ] Config hierarchy: defaults -> config.exs -> module options

## Phase 6: Testing and Validation

### Test NIFs (C3)
- [ ] `test/native/primitives.c3` - Basic type tests
- [ ] `test/native/safety.c3` - Error handling tests
- [ ] `test/native/resource.c3` - Resource lifecycle with atomic counters

### Integration Tests
- [x] `test/integration/nif_loading_test.exs` - End-to-end NIF compilation, loading, and execution
- [ ] `test/integration/primitives_test.exs` - Type marshalling
- [x] `test/integration/binary_test.exs` - Binary handling
- [x] `test/integration/resource_basic_test.exs` - Basic resource operations and atomic counter pattern
- [x] `test/integration/resource_cleanup_test.exs` - Destructor message passing (Zigler pattern)
- [x] `test/integration/resource_keep_test.exs` - Keep/release reference counting
- [x] `test/integration/resource_monitor_test.exs` - Down callbacks (process monitoring)
- [x] `test/integration/allocator_test.exs` - BEAM allocator operations
- [x] `test/integration/safety_test.exs` - Safety hardening (27 tests)
  - [x] Argument bounds checking and validation
  - [x] Type validation (int, uint, long, double, atom, binary, list, tuple, map, pid)
  - [x] Range validation (require_int_range, require_non_negative, require_positive)
  - [x] Nested fault propagation
  - [x] Custom fault handling (ARGC_MISMATCH)
- [x] `test/integration/scheduler_test.exs` - Scheduler support (12 tests)
  - [x] Thread type detection (normal, dirty_cpu, dirty_io)
  - [x] Process liveness checks
  - [x] Timeslice consumption
  - [x] Static dirty scheduler declaration
  - [x] Dynamic scheduling (normal→dirty→normal)
- [x] `test/integration/codegen_test.exs` - Code generation (6 tests)
  - [x] Auto-generated entry point with multiple NIFs
  - [x] Custom Elixir name via `name = "..."` annotation
  - [x] Auto-detected `on_load` callback wiring
  - [x] Dirty CPU scheduler via `dirty = cpu` annotation
  - [x] Dirty IO scheduler via `dirty = io` annotation

### Safety Tests
- [x] `test/integration/safety_test.exs` - Errors become tuples, not BEAM crash
- [ ] `test/safety/resource_test.exs` - GC cleanup with atomic counter verification
- [ ] `test/safety/lifecycle_test.exs` - on_load/upgrade/unload callbacks

### Memory Testing (External Tooling)
- [ ] Valgrind integration for leak detection
- [ ] CI job for memory testing

### CI Infrastructure
- [ ] `.github/workflows/test.yml` - Linux CI with OTP/Elixir matrix
- [ ] Optional Valgrind job for memory leak detection

## Phase 7: Cross-Platform Support

- [x] Linux x86_64 support (primary development platform)
- [ ] Linux aarch64 support
- [ ] macOS x86_64 support
- [ ] macOS aarch64 (Apple Silicon) support
- [ ] Windows support
- [ ] Cross-compilation support
- [ ] Precompiled artifact distribution

## Phase 8: Developer Experience

### Documentation
- [ ] API reference documentation
- [ ] Migration guide from C NIFs
- [ ] Migration guide from Rustler
- [ ] Performance optimization guide
- [ ] Debugging guide (GDB/LLDB with C3 NIFs)
- [ ] Common pitfalls and footguns
- [ ] Scheduler impact profiling guide

### Tooling
- [ ] Error messages with source locations
- [ ] Example projects
  - [ ] Basic math operations
  - [ ] String processing
  - [ ] Resource management
  - [ ] Async/threaded operations

## Phase 9: Advanced Features

- [ ] Binary/iolist zero-copy support
- [ ] Large binary handling optimization
- [ ] Port driver support
- [ ] Hot code reloading (on_upgrade implementation)
- [ ] OTP release integration
- [ ] enif_binary_to_term / enif_term_to_binary support

## Phase 10: Safety Hardening

- [ ] Audit all FFI boundaries for null pointer safety
- [ ] Verify all term references respect environment lifetimes
- [ ] Test resource cleanup under GC pressure
- [ ] Validate thread-safety of all shared state
- [ ] Memory safety review of all allocations
- [ ] Fuzz testing for type marshalling

## Future Considerations

- C integration via C3's extern functions
- Nerves/embedded system support
- Hex.pm package publishing
- CI/CD templates for NIF projects
- NIF tracing and debugging hooks
- Performance profiling integration
