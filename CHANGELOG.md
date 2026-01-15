# Changelog

## [0.1.1] - 2026-01-15

### Fixed
- Fix `Application.app_dir/2` error during initial compilation of projects using c3nif

## [Unreleased]

### Added
- Initial release
- C3 NIF runtime library with type-safe term handling
- Resource management with destructors and process monitoring
- Dirty scheduler support (CPU and IO bound)
- BEAM-tracked memory allocator
- Mix compiler integration
- `~n` sigil for inline C3 code
- Automatic NIF entry point generation via `<* nif: *>` annotations
