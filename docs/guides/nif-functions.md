# NIF Functions

This guide covers how to define and configure NIF functions in C3nif.

## NIF Function Signature

Every NIF function must follow this exact signature:

```c3
fn erl_nif::ErlNifTerm function_name(
    erl_nif::ErlNifEnv* raw_env,
    CInt argc,
    erl_nif::ErlNifTerm* argv
)
```

- `raw_env` - The NIF environment handle
- `argc` - Number of arguments passed (should match your declared arity)
- `argv` - Array of argument terms

## NIF Annotations

NIF functions are marked with the `<* nif: ... *>` annotation in C3 doc comment syntax:

```c3
<* nif: arity = 2 *>
fn erl_nif::ErlNifTerm add(
    erl_nif::ErlNifEnv* raw_env,
    CInt argc,
    erl_nif::ErlNifTerm* argv
) {
    // implementation
}
```

### Available Annotation Options

| Option | Type | Description |
|--------|------|-------------|
| `arity` | integer | Number of Elixir arguments (required) |
| `name` | string | Custom Elixir function name |
| `dirty` | `cpu` or `io` | Run on dirty scheduler |

### Custom Function Names

Use `name` to expose a different name to Elixir:

```c3
<* nif: name = "my_function", arity = 1 *>
fn erl_nif::ErlNifTerm internal_impl(
    erl_nif::ErlNifEnv* raw_env,
    CInt argc,
    erl_nif::ErlNifTerm* argv
) {
    // ...
}
```

In Elixir, this becomes `my_function/1`, not `internal_impl/1`.

### Dirty Schedulers

For long-running operations, use dirty schedulers:

```c3
<* nif: arity = 1, dirty = cpu *>
fn erl_nif::ErlNifTerm cpu_intensive(
    erl_nif::ErlNifEnv* raw_env,
    CInt argc,
    erl_nif::ErlNifTerm* argv
) {
    // CPU-bound work
}

<* nif: arity = 1, dirty = io *>
fn erl_nif::ErlNifTerm io_bound(
    erl_nif::ErlNifEnv* raw_env,
    CInt argc,
    erl_nif::ErlNifTerm* argv
) {
    // I/O operations
}
```

See the [Dirty Schedulers](dirty-schedulers.md) guide for more details.

## Elixir Stubs

Every NIF needs a corresponding Elixir function stub:

```elixir
defmodule MyModule do
  use C3nif, otp_app: :my_app

  ~c3"""
  // ... C3 code ...
  """

  # Stubs - called if NIF not loaded
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def multiply(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
```

These stubs:
1. Define the function arity for the Erlang VM
2. Provide a fallback if the NIF fails to load
3. Can include documentation via `@doc`

## Accessing Arguments

Wrap raw arguments before use:

```c3
env::Env e = env::wrap(raw_env);
term::Term arg0 = term::wrap(argv[0]);
term::Term arg1 = term::wrap(argv[1]);
```

### Using Safety Helpers

C3nif provides helpers for safer argument access:

```c3
import c3nif::safety;

fn erl_nif::ErlNifTerm my_nif(
    erl_nif::ErlNifEnv* raw_env,
    CInt argc,
    erl_nif::ErlNifTerm* argv
) {
    env::Env e = env::wrap(raw_env);

    // Validate argument count
    if (safety::require_argc(argc, 2)) |err| {
        return err.raw();
    }

    // Get typed arguments
    int? a = safety::require_int(&e, argv, 0);
    if (catch err = a) {
        return term::make_badarg(&e).raw();
    }

    int? b = safety::require_int(&e, argv, 1);
    if (catch err = b) {
        return term::make_badarg(&e).raw();
    }

    return term::make_int(&e, a + b).raw();
}
```

## Return Values

Always return an `erl_nif::ErlNifTerm`. Use the `.raw()` method on wrapped terms:

```c3
// Return an integer
return term::make_int(&e, 42).raw();

// Return an atom
return term::make_atom(&e, "ok").raw();

// Return a tuple {:ok, value}
return term::make_ok_tuple(&e, term::make_int(&e, result)).raw();

// Return an error tuple {:error, reason}
return term::make_error_tuple(&e, term::make_atom(&e, "invalid_input")).raw();

// Signal argument error (raises ArgumentError in Elixir)
return term::make_badarg(&e).raw();
```

## Lifecycle Callbacks

C3nif automatically detects `on_load` and `on_unload` callbacks:

```c3
// Called when NIF is loaded
fn CInt on_load(
    erl_nif::ErlNifEnv* env,
    void** priv,
    erl_nif::ErlNifTerm load_info
) {
    // Initialize resources, state, etc.
    return 0;  // 0 = success
}

// Called when NIF is unloaded
fn void on_unload(
    erl_nif::ErlNifEnv* env,
    void* priv
) {
    // Cleanup resources
}
```

These callbacks are detected by their function names and signatures.

## Multiple NIFs in One Module

You can define multiple NIFs in a single module:

```elixir
defmodule MyApp.Math do
  use C3nif, otp_app: :my_app

  ~c3"""
  module math;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  <* nif: arity = 2 *>
  fn erl_nif::ErlNifTerm add(...) { /* ... */ }

  <* nif: arity = 2 *>
  fn erl_nif::ErlNifTerm subtract(...) { /* ... */ }

  <* nif: arity = 2 *>
  fn erl_nif::ErlNifTerm multiply(...) { /* ... */ }

  <* nif: arity = 2 *>
  fn erl_nif::ErlNifTerm divide(...) { /* ... */ }
  """

  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def subtract(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def multiply(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def divide(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
```

## Code Organization

For larger NIFs, split your C3 code into multiple `~c3` blocks:

```elixir
defmodule MyApp.Nif do
  use C3nif, otp_app: :my_app

  # Module declaration and imports
  ~c3"""
  module mynif;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  """

  # Helper functions
  ~c3"""
  fn int helper_function(int x) {
      return x * 2;
  }
  """

  # NIF implementations
  ~c3"""
  <* nif: arity = 1 *>
  fn erl_nif::ErlNifTerm process(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      // ...
  }
  """

  def process(_data), do: :erlang.nif_error(:nif_not_loaded)
end
```

All `~c3` blocks are concatenated before compilation.

### External Source Files

For even better organization, use the `:c3_sources` option to include external C3 files:

```elixir
defmodule MyApp.Nif do
  use C3nif,
    otp_app: :my_app,
    c3_sources: [
      "c3_src/helpers.c3",
      "c3_src/utils/**/*.c3"
    ]

  ~c3"""
  module mynif;

  import c3nif;
  import c3nif::erl_nif;
  import helpers;  // External module

  <* nif: arity = 1 *>
  fn erl_nif::ErlNifTerm process(...) { /* ... */ }
  """

  def process(_data), do: :erlang.nif_error(:nif_not_loaded)
end
```

External sources support glob patterns (`**/*.c3`) for matching multiple files. See the [Getting Started](getting-started.md#external-c3-sources) guide for more details.

## Best Practices

1. **Keep NIFs short** - NIFs should complete quickly (< 1ms). Use dirty schedulers for longer operations.

2. **Validate arguments early** - Check types and ranges before doing work.

3. **Handle all error cases** - Return badarg or error tuples for invalid input.

4. **Document your NIFs** - Use `@doc` on Elixir stubs to document behavior.

5. **Test thoroughly** - NIFs can crash the VM if written incorrectly.
