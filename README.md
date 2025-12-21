# C3nif

**Ergonomic Erlang/Elixir NIFs using C3**

C3nif is a library for writing Erlang/Elixir Native Implemented Functions (NIFs) using the [C3 programming language](https://c3-lang.org). If you know C but find raw NIF code tedious, C3nif gives you a cleaner API with less boilerplate.

## Why C3nif?

- **Performance**: Compiles to native code, same as C
- **Less boilerplate**: Wrapper types and helpers cut down on repetitive NIF code
- **Explicit error handling**: C3's optional types (`int?`) make error paths visible
- **Familiar syntax**: If you know C, you can read C3
- **Not Rust**: No borrow checker to fight with (but also no memory safety guarantees)

## Quick Example

```elixir
defmodule MyApp.Math do
  use C3nif, otp_app: :my_app

  ~n"""
  module math_nif;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  fn ErlNifTerm add_one(
      ErlNifEnv* raw_env,
      CInt argc,
      ErlNifTerm* argv
  ) {
      Env e = env::wrap(raw_env);
      Term arg0 = term::wrap(argv[0]);

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

### Type Conversions

C3nif wraps Erlang terms in a `Term` type with methods that return optionals on failure:

```c3
fn ErlNifTerm double_it(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);
    Term arg = term::wrap(argv[0]);

    // Returns optional - you handle the error or it won't compile
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
Env e = env::wrap(raw_env);

// Process-independent (for async operations)
env::OwnedEnv? owned = env::new_owned_env();
if (catch err = owned) {
    // Handle allocation failure
}
Env async_env = owned.as_env();
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
Term result = term::make_int(&e, 42);
int? extracted = arg.get_int(&e);

// List operations
Term empty = term::make_empty_list(&e);
Term list = term::make_list_cell(&e, head, tail);

// Map operations
Term map = term::make_new_map(&e);
Term? updated = map.map_put(&e, key, value);

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
    Env e = env::wrap(env_raw);
    resource::register_type(&e, "Counter", &counter_dtor)!!;
    return 0;
}

// Create a resource
fn ErlNifTerm create_counter(ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv) {
    Env e = env::wrap(env_raw);

    void* ptr = resource::alloc("Counter", Counter.sizeof)!!;
    Counter* c = (Counter*)ptr;
    c.value = 42;

    Term t = resource::make_term(&e, ptr);
    resource::release(ptr);  // Term now owns the reference
    return t.raw();
}

// Use a resource
fn ErlNifTerm get_counter(ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv) {
    Env e = env::wrap(env_raw);
    Term arg = term::wrap(argv[0]);

    void* ptr = resource::get("Counter", &e, arg)!!;
    Counter* c = (Counter*)ptr;

    return term::make_int(&e, c.value).raw();
}
```

### Memory Allocation

BEAM-tracked memory allocation for use with C3 standard library collections:

```c3
import c3nif::allocator;

// Simple allocation
void* ptr = allocator::alloc(1024);
if (!ptr) {
    return term::make_error_atom(&e, "alloc_failed").raw();
}
defer allocator::free(ptr);

// Zero-initialized allocation
void* zeroed = allocator::calloc(256);

// Reallocation (preserves data)
void* grown = allocator::realloc(ptr, 2048);

// With C3 Allocator interface (for collections)
allocator::BeamAllocator beam;
List{int} numbers;
numbers.init(&beam);
defer numbers.free();
```

**Thread Safety**: All allocator functions are thread-safe and can be called from any thread (scheduler, dirty scheduler, or user-created).

**VM Integration**: All allocations are tracked by the BEAM VM and visible in `erlang:memory()` reports.

**Strict Pairing**: Memory allocated with `allocator::alloc` must be freed with `allocator::free`. Never mix with system `malloc`/`free`, binary allocators, or resource allocators.

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

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - Internal architecture and design decisions
- [Roadmap](docs/ROADMAP.md) - Development progress and planned features
- [Thread-Safety](docs/THREAD_SAFETY.md) - Thread-safety guide for dirty schedulers and async operations
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
- Linux x86_64

## You Can Still Crash the VM

C3nif makes NIFs more ergonomic, but it doesn't make them memory-safe. You're still writing native code. Things that will crash your VM:

- Segfaults from null pointers or use-after-free
- Buffer overflows
- Storing terms beyond their environment's lifetime
- Using `!!` to unwrap errors instead of handling them

The `!!` operator is convenient but dangerous - it panics on error:

```c3
// This will crash if allocation fails:
void* ptr = resource::alloc("Counter", Counter.sizeof)!!;

// Prefer explicit handling:
void*? ptr = resource::alloc("Counter", Counter.sizeof);
if (catch err = ptr) {
    return term::make_error_atom(&e, "alloc_failed").raw();
}
```

Other things to remember:
- Keep NIFs under 1ms (or use dirty schedulers)
- Test edge cases - bad input shouldn't crash the VM
- Run with AddressSanitizer during development

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Note**: This project is in active development. The API may change before version 1.0.0.
