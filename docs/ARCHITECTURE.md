# Architecture

This document describes the internal architecture of C3nif and provides guidance for contributors.

**Reference implementations**: [Rustler](https://github.com/rusterlium/rustler) and [Zigler](https://github.com/E-xyza/zigler) serve as architectural references.

## Two-Layer Architecture

C3nif follows a two-layer architecture:

### 1. C3 Runtime Library (`c3nif.c3l/`)

A C3 library providing safe wrappers around the Erlang NIF C API:

```
c3nif.c3l/
├── manifest.json        # C3 library manifest
├── project.json         # C3 project configuration
├── erl_nif.c3          # FFI bindings to erl_nif.h
├── env.c3              # Environment management (Env, OwnedEnv)
├── term.c3             # Term encoding/decoding with type safety
└── c3nif.c3            # Main module facade with type aliases
```

#### erl_nif.c3 - FFI Bindings

Complete bindings to the Erlang NIF C API:

```c3
// Type definitions
alias ErlNifTerm = CULong;
alias ErlNifEnv = void;

// Struct definitions
struct ErlNifEntry {
    CInt major;
    CInt minor;
    char* name;
    CInt num_of_funcs;
    ErlNifFunc* funcs;
    // ... lifecycle callbacks
}

// External function declarations
extern fn ErlNifTerm enif_make_int(ErlNifEnv*, CInt) @extern("enif_make_int");
extern fn CInt enif_get_int(ErlNifEnv*, ErlNifTerm, CInt*) @extern("enif_get_int");
// ... 50+ NIF API functions
```

#### env.c3 - Environment Management

Safe wrappers around environment operations:

```c3
// Process-bound environment wrapper
struct Env {
    erl_nif::ErlNifEnv* inner;
}

// Process-independent environment for async operations
struct OwnedEnv {
    erl_nif::ErlNifEnv* inner;
}

// Fault definitions for error handling
faultdef NO_PROCESS;
faultdef ALLOC_FAILED;

// Safe operations
fn erl_nif::ErlNifPid? Env.self(&self) {
    erl_nif::ErlNifPid pid;
    if (erl_nif::enif_self(self.inner, &pid) == null) {
        return NO_PROCESS?;
    }
    return pid;
}
```

#### term.c3 - Term Operations

Type-safe term encoding and decoding:

```c3
struct Term {
    erl_nif::ErlNifTerm inner;
}

// Fault definitions
faultdef BADARG;
faultdef OVERFLOW;
faultdef ENCODING;

// Type checking
fn bool Term.is_atom(&self, env::Env* e) {
    return erl_nif::enif_is_atom(e.inner, self.inner) != 0;
}

// Safe extraction with optionals
fn int? Term.get_int(&self, env::Env* e) {
    CInt result;
    if (erl_nif::enif_get_int(e.inner, self.inner, &result) == 0) {
        return BADARG?;
    }
    return (int)result;
}

// Operator overloading for comparison
fn bool Term.equals(self, Term other) @operator(==) {
    return erl_nif::enif_is_identical(self.inner, other.inner) != 0;
}
```

### 2. Mix Integration (`lib/`)

Elixir modules for compilation and integration:

```
lib/
├── c3nif.ex              # Main module with use macro and ~c3 sigil
└── c3nif/
    └── compiler.ex       # Compilation orchestration
```

#### c3nif.ex - Main Module

```elixir
defmodule C3nif do
  defmacro __using__(opts) do
    # Validate otp_app option
    # Register module attributes for code accumulation
    # Set up @on_load and @before_compile hooks
    quote do
      @c3nif_opts unquote(opts)
      import C3nif, only: [sigil_c3: 2]
      @on_load :__load_nifs__
      @before_compile C3nif.Compiler
    end
  end

  # Sigil for inline C3 code
  defmacro sigil_c3({:<<>>, meta, [c3_code]}, []) do
    quote do
      @c3_code_parts "// ref #{file}:#{line}\n"
      @c3_code_parts c3_code
    end
  end
end
```

#### compiler.ex - Compilation

```elixir
defmodule C3nif.Compiler do
  defmacro __before_compile__(%{module: module}) do
    # 1. Collect accumulated C3 code from module attributes
    # 2. Create staging directory in /tmp
    # 3. Generate project.json for c3c
    # 4. Symlink c3nif.c3l library
    # 5. Write C3 source file
    # 6. Invoke c3c build
    # 7. Generate __load_nifs__/0 function
  end

  def compile(opts) do
    # Standalone compilation function for testing
  end
end
```

## Compilation Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│ Elixir Module with `use C3nif, otp_app: :my_app`           │
│                                                             │
│   ~c3"""                                                    │
│   module my_nif;                                            │
│   import c3nif;                                             │
│   // ... NIF code                                           │
│   """                                                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ @before_compile (C3nif.Compiler)                           │
│                                                             │
│ 1. Collect @c3_code_parts                                  │
│ 2. Create staging directory: /tmp/.c3nif_compiler/Module   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Staging Directory Structure                                 │
│                                                             │
│ /tmp/.c3nif_compiler/Elixir.MyModule/                      │
│ ├── project.json          # Generated C3 project config    │
│ ├── Elixir.MyModule.c3    # User's C3 code                 │
│ └── lib/                                                    │
│     └── c3nif.c3l -> /path/to/c3nif/c3nif.c3l (symlink)   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ c3c build                                                   │
│                                                             │
│ Compiles C3 code to shared library:                        │
│ build/Elixir.MyModule.so                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Generated Elixir Code                                       │
│                                                             │
│ def __load_nifs__ do                                       │
│   nif_path = Application.app_dir(@otp_app, "priv")         │
│              |> Path.join(@nif_name)                       │
│   :erlang.load_nif(nif_path, 0)                            │
│ end                                                         │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

### Library Structure (c3nif itself)

```
c3nif/
├── lib/
│   ├── c3nif.ex                    # Main module, use macro, ~c3 sigil
│   └── c3nif/
│       └── compiler.ex             # Compilation orchestration
├── c3nif.c3l/                      # C3 runtime library
│   ├── manifest.json               # C3 library manifest
│   ├── project.json                # C3 project config
│   ├── erl_nif.c3                  # FFI bindings to erl_nif.h
│   ├── env.c3                      # Environment management
│   ├── term.c3                     # Term encoding/decoding
│   └── c3nif.c3                    # Main module facade
├── test/
│   ├── test_helper.exs             # ExUnit setup
│   ├── support/
│   │   └── c3nif_case.ex           # Test case helpers
│   ├── c3nif_test.exs              # Basic tests
│   └── c3nif/
│       └── compiler_test.exs       # Compiler integration tests
├── docs/
│   ├── ARCHITECTURE.md             # This file
│   ├── ROADMAP.md                  # Development progress
│   └── TESTING_RESEARCH.md         # Testing patterns research
└── mix.exs
```

### User Project Structure (apps using c3nif)

```
my_app/
├── lib/
│   └── my_app/
│       └── nif.ex                  # Module with use C3nif
├── priv/
│   └── libElixir.MyApp.Nif.so      # Compiled NIF (after build)
└── mix.exs
```

## Type Marshalling

### Supported Conversions

| Erlang/Elixir | C3 Type | Make Function | Get Function |
|---------------|---------|---------------|--------------|
| `integer()` | `int` | `make_int` | `get_int` |
| `integer()` | `uint` | `make_uint` | `get_uint` |
| `integer()` | `long` | `make_long` | `get_long` |
| `integer()` | `ulong` | `make_ulong` | `get_ulong` |
| `float()` | `double` | `make_double` | `get_double` |
| `atom()` | `char*` | `make_atom` | (via atom_length) |
| `binary()` | `ErlNifBinary` | `make_new_binary` | `inspect_binary` |
| `list()` | `ErlNifTerm[]` | `make_list_from_array` | `get_list_cell` |
| `tuple()` | `ErlNifTerm[]` | `make_tuple_from_array` | `get_tuple` |
| `map()` | - | `make_new_map` | `map_get` |
| `reference()` | - | `make_ref` | `is_ref` |
| `pid()` | `ErlNifPid` | - | `get_local_pid` |

### Error Handling Pattern

C3nif uses C3's optional types for safe error handling:

```c3
fn int? Term.get_int(&self, env::Env* e) {
    CInt result;
    if (erl_nif::enif_get_int(e.inner, self.inner, &result) == 0) {
        return BADARG?;  // Return fault
    }
    return (int)result;
}

// Usage in NIF:
fn ErlNifTerm my_nif(ErlNifEnv* raw_env, CInt argc, ErlNifTerm* argv) {
    Env e = env::wrap(raw_env);
    Term arg = term::wrap(argv[0]);

    int? value = arg.get_int(&e);
    if (catch err = value) {
        return term::make_badarg(&e).raw();
    }

    return term::make_int(&e, value + 1).raw();
}
```

## Environment Lifetime Management

### Process-Bound Environments

Standard NIF calls receive a process-bound environment:

```c3
fn ErlNifTerm my_nif(ErlNifEnv* raw_env, CInt argc, ErlNifTerm* argv) {
    Env e = env::wrap(raw_env);
    // Terms created here are valid until NIF returns
    Term result = term::make_int(&e, 42);
    return result.raw();  // OK - returned immediately
}
```

### Process-Independent Environments (OwnedEnv)

For async operations or storing terms across NIF calls:

```c3
// Create owned environment (can outlive NIF call)
OwnedEnv? owned = env::new_owned_env();
if (catch err = owned) {
    // Handle allocation failure
}

// Build terms in owned environment
Env e = owned.as_env();
Term term = term::make_int(&e, 42);

// Send to process
owned.send(null, &pid, term.raw());

// Clear or free when done
owned.clear();  // Reuse environment
owned.free();   // Destroy environment
```

## C3 Language Patterns

### Struct Initialization

```c3
// Must use parenthesized compound literal in return statements
fn Env wrap(ErlNifEnv* raw) {
    return (Env){ .inner = raw };
}
```

### Fault Definitions

```c3
// Define faults at module level
faultdef BADARG;
faultdef NO_PROCESS;

// Return faults with ?
fn int? get_value() {
    if (error_condition) {
        return BADARG?;
    }
    return 42;
}
```

### Optional Types

```c3
// Type? indicates optional return
fn int? Term.get_int(&self, env::Env* e) {
    // ...
}

// Handle with catch
int? result = term.get_int(&e);
if (catch err = result) {
    // Handle error
}
```

### Operator Overloading

```c3
fn bool Term.equals(self, Term other) @operator(==) {
    return erl_nif::enif_is_identical(self.inner, other.inner) != 0;
}

// Enables: if (term1 == term2) { ... }
```

## Configuration

### Generated project.json

```json
{
  "langrev": "1",
  "warnings": ["no-unused"],
  "dependency-search-paths": ["lib"],
  "dependencies": ["c3nif"],
  "version": "0.1.0",
  "sources": ["ModuleName.c3"],
  "output": "build",
  "targets": {
    "ModuleName": {
      "type": "dynamic-lib",
      "reloc": "pic"
    }
  },
  "cc": "cc",
  "linker": "cc",
  "link-libc": true,
  "opt": "O0"
}
```

## Known Limitations

### AddressSanitizer with Dynamic Libraries

C3 currently uses lld (LLVM linker) directly for dynamic libraries even when `"linker": "cc"` is specified. Since lld doesn't understand `-fsanitize=address`, ASan cannot be enabled for the c3nif library directly.

**Workaround**: Use external tooling for memory leak detection:
- Valgrind: `valgrind --leak-check=full mix test`
- ASan via LD_PRELOAD: `LD_PRELOAD=/usr/lib/libasan.so mix test`

## Key Patterns from Reference Implementations

### From Rustler

- **Config hierarchy**: Defaults → `config.exs` → module `use` options
- **OwnedEnv**: Process-independent term building
- **Error isolation**: Catch errors to prevent BEAM crashes

### From Zigler

- **Staged compilation**: Never compile in-place, use temp directories
- **Sigil-based code**: `~Z` / `~c3` for inline native code
- **Before compile hook**: Compile during module compilation phase
