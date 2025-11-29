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
- [ ] `priv/c3nif/binary.c3` - Binary handling
  - [ ] Zero-copy binary inspection
  - [ ] Reference-counted binary handling
  - [ ] enif_keep_binary/enif_release_binary
  - [ ] Sub-binary creation
  - [ ] Heap vs refc binary threshold (64 bytes)

### Resource Management
- [x] `resource.c3` - Full resource management
  - [x] Resource type registration
  - [x] Destructor callbacks
  - [x] Down callbacks (process monitoring)
  - [x] Thread-safety documentation

### Allocator Integration
- [ ] `allocator.c3` - BEAM allocator wrappers
  - [ ] BeamAllocator struct
  - [ ] Strict allocator pairing enforcement

### Safety Hardening
- [ ] `safety.c3` - Error isolation
  - [ ] NIF entry point wrappers
  - [ ] Error boundary enforcement
  - [ ] Panic prevention

## Phase 3: Scheduler Support

### Timeslice Management
- [ ] `enif_consume_timeslice` high-level wrapper
- [ ] Yielding NIF support (`enif_schedule_nif`)
- [ ] Execution time profiling utilities

### Dirty Schedulers
- [x] FFI bindings for dirty scheduler flags
- [ ] High-level dirty scheduler integration (`@nif("name", dirty: .cpu)`)
- [ ] Documentation of dirty scheduler limitations
  - [ ] Which enif_* functions are unavailable
  - [ ] Process dictionary restrictions
  - [ ] Message receiving restrictions

## Phase 4: Code Generation

- [ ] Parse C3 source for `@nif` annotations
- [ ] Generate `ErlNifEntry` struct automatically
- [ ] Automatic NIF function collection (inventory pattern)
- [ ] Generate Elixir function stubs
- [ ] Generate module lifecycle callback wrappers
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
- [ ] `test/integration/binary_test.exs` - Binary handling
- [x] `test/integration/resource_basic_test.exs` - Basic resource operations and atomic counter pattern
- [x] `test/integration/resource_cleanup_test.exs` - Destructor message passing (Zigler pattern)
- [x] `test/integration/resource_keep_test.exs` - Keep/release reference counting
- [x] `test/integration/resource_monitor_test.exs` - Down callbacks (process monitoring)

### Safety Tests
- [ ] `test/safety/crash_test.exs` - Errors become exceptions, not BEAM crash
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
