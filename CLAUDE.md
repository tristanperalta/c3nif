# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

C3nif is a library for writing Erlang/Elixir NIFs (Native Implemented Functions) using the C3 programming language. It provides type-safe conversions, resource management, and error handling between Erlang/Elixir and C3.

**Reference implementations**:
- Rustler (`/home/tristan/sources/rustler`) - Rust NIF framework
- Zigler (`/home/tristan/sources/zigler`) - Zig NIF framework
- Nx (`/home/tristan/sources/nx`) - Numerical Elixir with EXLA and Torchx NIF backends

## Build & Development Commands

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run a single test file
mix test test/path/to/test_file_test.exs

# Run a specific test by line number
mix test test/path/to/test_file_test.exs:42
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation.

**Summary**: Three-layer architecture with C3 runtime library (`priv/c3nif/`), Mix integration (`lib/c3nif/`), and code generation.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for development progress and planned features.

## Testing

See [docs/TESTING_RESEARCH.md](docs/TESTING_RESEARCH.md) for testing patterns from Rustler, Zigler, and Nx.

**Key testing decisions**:
- Leak detection via external tooling (Valgrind/ASan)
- Resource cleanup tracked with atomic counters
- CI initially Linux-only

## C3 NIF Conventions

- NIF functions use `@nif("name")` attribute annotation
- Resource types use `@resource_type` attribute
- Dirty scheduler NIFs use `@nif("name", dirty: .cpu)` or `dirty: .io`
- Error handling uses C3's optional types with `!` suffix and `??` operator
- NIFs should complete in under 1ms or use dirty schedulers

## Dependencies

- C3 compiler version 0.8.0 or later (https://c3-lang.org)
- Erlang/OTP 29 (NIFs build against ERL_NIF 2.17, so they still load on OTP 26+)
- Elixir 1.20 or later with Mix build tool
