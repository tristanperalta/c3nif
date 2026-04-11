# Changelog

## [0.2.0] - 2026-04-11

Modernization release: C3 0.7.11 + ERL_NIF 2.17 (OTP 26+), with a new
precompiled NIF distribution pipeline.

### Breaking

- **Minimum C3 compiler version is now 0.7.11** (was 0.6.0). Updates all
  source to the current C3 syntax: `enum Foo : const CInt` declarations
  were converted to `constdef X : inline CInt`, and fault-creation sites
  use `return X~;` instead of the deprecated `return X?;`.
- **Minimum OTP version is now 26** (was effectively OTP 21). Required
  for ERL_NIF 2.17 APIs such as `enif_make_new_atom`, `enif_set_option`,
  and UTF-8 atom encoding.
- **Resource registry API hard break.** The O(n) string-keyed lookup has
  been removed. `resource::register_type` now returns an
  `ErlNifResourceType*` handle that callers must cache at load time,
  and both `resource::alloc` and `resource::get` take that handle
  instead of a string name. The 32-type cap (`MAX_RESOURCE_TYPES`) and
  the internal registry arrays are gone. `get_resource` macro and
  `c3nif.c3` aliases were updated to match. See `guides/resources.md`
  for the new pattern.

### Added

- **ERL_NIF 2.17 API surface.** Bound `enif_make_new_atom`,
  `enif_make_new_atom_len`, `enif_get_string_length`, and the three
  `enif_set_option` variants (`DELAY_HALT`, `ON_HALT`,
  `ON_UNLOAD_THREAD`). Added the `ErlNifCharEncoding.UTF8` variant and
  `ErlNifOption`, `OnHaltFn`, `OnUnloadThreadFn` types.
- **UTF-8 atom helpers** in `term.c3`: `make_atom_utf8`,
  `make_atom_utf8_len`, `make_existing_atom_utf8`. Unlike the older
  `make_atom` path, these return an `ATOM_TABLE_FULL` fault instead of
  aborting the VM when the atom table is exhausted.
- **Halt-safety wrappers** in `scheduler.c3`: `delay_halt`,
  `set_on_halt`, `set_on_unload_thread`. Use from a NIF's load callback
  to keep long-running dirty NIFs from being killed mid-operation
  during `init:stop/0,1`.
- **Precompiled NIF distribution.** New `C3nif.Precompiled` module and
  `mix c3nif.precompile` task for building, archiving, and SHA-256
  verifying prebuilt shared libraries per target triple. Consumers opt
  in via `use C3nif, precompiled: [base_url: ..., version: ...,
  checksums_path: ...]` and get automatic source-build fallback when a
  precompiled artifact isn't available. Mirrors the
  `rustler_precompiled` workflow. See `guides/precompilation.md`.

### Changed

- `C3nif.Compiler.compile/1` now accepts an optional `:target` key that
  is forwarded to `c3c build --target <triple>`. The c3c invocation was
  refactored into a shared `run_c3c/2` helper used by both the regular
  compile path and the precompile task.
- Removed the unused `jason` dependency; C3nif uses the stdlib `JSON`
  module (Elixir 1.18+).

### Fixed

- `test/integration/binary_test.exs` copy-binary assertion no longer
  depends on OTP 25 internal allocation-size reporting.

## [0.1.2] - 2026-01-15

### Fixed
- Fix `c3nif_src_path` to work with path dependencies using `__DIR__`

## [0.1.1] - 2026-01-15

### Fixed
- Fix `Application.app_dir/2` errors during initial compilation of projects using c3nif

## [0.1.0]

### Added
- Initial release
- C3 NIF runtime library with type-safe term handling
- Resource management with destructors and process monitoring
- Dirty scheduler support (CPU and IO bound)
- BEAM-tracked memory allocator
- Mix compiler integration
- `~n` sigil for inline C3 code
- Automatic NIF entry point generation via `<* nif: *>` annotations
