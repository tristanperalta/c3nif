# C3nif

**Safe and ergonomic Erlang/Elixir NIFs using C3**

C3nif is a library for writing Erlang/Elixir Native Implemented Functions (NIFs) using the [C3 programming language](https://c3-lang.org). It provides a safe, modern alternative to writing NIFs in C while maintaining excellent performance and familiar syntax.

## Status

**Phase 1 Complete** - Core foundation implemented:
- C3 runtime library with FFI bindings, environment management, and term operations
- Mix integration with `use C3nif` macro and `~c3` sigil
- Compilation pipeline with staging directories
- Test infrastructure

**Phase 2 In Progress** - Advanced runtime features:
- Resource management with type registration, destructor callbacks, and reference counting

## Why C3nif?

- **Performance**: Compiles to efficient native code, comparable to C
- **Safety**: C3's modern error handling with optionals reduces NIF crashes
- **Ergonomic**: Clean, readable syntax with type-safe conversions
- **Familiar**: C-like syntax that's easier to learn than Rust or Zig
- **Fast Development**: Minimal boilerplate compared to raw C NIFs

## Quick Example

```elixir
defmodule MyApp.Math do
  use C3nif, otp_app: :my_app

  ~c3"""
  module math_nif;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  fn erl_nif::ErlNifTerm add_one(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      term::Term arg0 = term::wrap(argv[0]);

      int? value = arg0.get_int(&e);
      if (catch err = value) {
          return term::make_badarg(&e).raw();
      }

      return term::make_int(&e, value + 1).raw();
  }
  """

  # Elixir function stub (will be replaced by NIF)
  def add_one(_n), do: :erlang.nif_error(:nif_not_loaded)
end
```

## Installation

Add `c3nif` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:c3nif, "~> 0.1.0"}
  ]
end
```

Ensure you have the C3 compiler installed:

```bash
# Install C3 compiler (version 0.7.7 or later required)
# See https://c3-lang.org/getting-started/prebuilt-binaries/
```

## Core Features

### Type-Safe Conversions

C3nif provides safe conversions between Erlang terms and C3 types using C3's optional types:

```c3
fn erl_nif::ErlNifTerm safe_double(
    erl_nif::ErlNifEnv* raw_env,
    CInt argc,
    erl_nif::ErlNifTerm* argv
) {
    env::Env e = env::wrap(raw_env);
    term::Term arg = term::wrap(argv[0]);

    // Safe extraction - returns optional
    int? value = arg.get_int(&e);
    if (catch err = value) {
        return term::make_badarg(&e).raw();
    }

    return term::make_int(&e, value * 2).raw();
}
```

### Environment Management

Process-bound and process-independent environments:

```c3
// Process-bound (standard NIF call)
env::Env e = env::wrap(raw_env);

// Process-independent (for async operations)
env::OwnedEnv? owned = env::new_owned_env();
if (catch err = owned) {
    // Handle allocation failure
}
env::Env async_env = owned.as_env();
// ... build terms, send messages ...
owned.free();
```

### Term Operations

Type checking, creation, and extraction:

```c3
// Type checking
if (arg.is_atom(&e)) { ... }
if (arg.is_list(&e)) { ... }

// Integer operations
term::Term result = term::make_int(&e, 42);
int? extracted = arg.get_int(&e);

// List operations
term::Term empty = term::make_empty_list(&e);
term::Term list = term::make_list_cell(&e, head, tail);

// Map operations
term::Term map = term::make_new_map(&e);
term::Term? updated = map.map_put(&e, key, value);

// Comparison (with operator overloading)
if (term1 == term2) { ... }
```

### Resource Management

Resources let you wrap native data structures and pass them to Erlang as opaque references:

```c3
import c3nif::resource;

// Define your native struct
struct Counter {
    int value;
}

// Destructor called when resource is garbage collected
fn void counter_dtor(ErlNifEnv* env, void* obj) {
    // Cleanup code here (Counter memory is freed automatically)
}

// Register in on_load callback
fn CInt on_load(ErlNifEnv* env_raw, void** priv, ErlNifTerm load_info) {
    env::Env e = env::wrap(env_raw);
    resource::register_type(&e, "Counter", &counter_dtor)!!;
    return 0;
}

// Create a resource
fn ErlNifTerm create_counter(ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv) {
    env::Env e = env::wrap(env_raw);

    void* ptr = resource::alloc("Counter", Counter.sizeof)!!;
    Counter* c = (Counter*)ptr;
    c.value = 42;

    term::Term t = resource::make_term(&e, ptr);
    resource::release(ptr);  // Term now owns the reference
    return t.raw();
}

// Use a resource
fn ErlNifTerm get_counter(ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv) {
    env::Env e = env::wrap(env_raw);
    term::Term arg = term::wrap(argv[0]);

    void* ptr = resource::get("Counter", &e, arg)!!;
    Counter* c = (Counter*)ptr;

    return term::make_int(&e, c.value).raw();
}
```

## Supported Types

| Erlang/Elixir | C3 Type | Operations |
|---------------|---------|------------|
| `integer()` | `int`, `uint`, `long`, `ulong` | `make_int`, `get_int`, etc. |
| `float()` | `double` | `make_double`, `get_double` |
| `atom()` | `char*` | `make_atom`, `make_existing_atom` |
| `binary()` | `ErlNifBinary` | `make_new_binary`, `inspect_binary` |
| `list()` | `ErlNifTerm[]` | `make_list_from_array`, `get_list_cell` |
| `tuple()` | `ErlNifTerm[]` | `make_tuple_from_array`, `get_tuple` |
| `map()` | - | `make_new_map`, `map_put`, `map_get` |
| `reference()` | - | `make_ref`, `is_ref` |
| `pid()` | `ErlNifPid` | `get_local_pid` |
| `resource()` | `void*` | `resource::alloc`, `resource::get`, `resource::make_term` |

## Project Structure

```
my_app/
├── lib/
│   └── my_app/
│       └── nif.ex                  # Module with use C3nif
├── priv/
│   └── libElixir.MyApp.Nif.so      # Compiled NIF (after build)
└── mix.exs
```

## Comparison with Other NIF Libraries

| Feature | C3nif | Rustler | Zigler | C NIFs |
|---------|-------|---------|--------|--------|
| **Syntax** | C-like | Rust | Zig | C |
| **Memory Safety** | Optionals | Ownership | Optionals | Manual |
| **Learning Curve** | Low | High | Medium | Low |
| **Performance** | Excellent | Excellent | Excellent | Excellent |
| **Ecosystem** | New | Mature | Growing | Native |
| **Error Handling** | Built-in | Result types | Built-in | Manual |

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - Internal architecture and design decisions
- [Roadmap](docs/ROADMAP.md) - Development progress and planned features
- [Testing Research](docs/TESTING_RESEARCH.md) - Testing patterns from Rustler, Zigler, and Nx

## Development

```bash
# Clone the repository
git clone https://github.com/tristanperalta/c3nif.git
cd c3nif

# Install dependencies
mix deps.get

# Run tests (automatically compiles C3 library)
mix test
```

## Requirements

- Elixir 1.18+
- C3 compiler 0.7.7+
- Linux x86_64 (other platforms coming soon)

## Safety Considerations

While C3nif is safer than raw C NIFs, you should still:

- Use C3nif's safe conversion functions with optional types
- Handle all potential errors with `if (catch err = ...)` patterns
- Keep NIFs under 1ms execution time (or use dirty schedulers)
- Test thoroughly, especially edge cases
- Don't store terms beyond their environment's lifetime
- Don't ignore error returns

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Note**: This project is in active development. The API may change before version 1.0.0.
