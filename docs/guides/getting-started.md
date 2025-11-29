# Getting Started

This guide walks you through creating your first NIF with C3nif.

## Prerequisites

- Elixir 1.18 or later
- [C3 compiler](https://c3-lang.org/) (c3c) installed and in your PATH
- Basic familiarity with Elixir and native code concepts

### Installing C3

Download the C3 compiler from [c3-lang.org](https://c3-lang.org/). On most systems:

```bash
# Verify installation
c3c --version
```

## Creating a New Project

Create a new Elixir project:

```bash
mix new my_nif_app
cd my_nif_app
```

Add C3nif as a dependency in `mix.exs`:

```elixir
defp deps do
  [
    {:c3nif, "~> 0.1.0"}
  ]
end
```

Fetch dependencies:

```bash
mix deps.get
```

## Your First NIF

Create a new module with a simple NIF that adds two integers:

```elixir
# lib/my_nif_app/math.ex
defmodule MyNifApp.Math do
  use C3nif, otp_app: :my_nif_app

  ~c3"""
  module math;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  <* nif: arity = 2 *>
  fn erl_nif::ErlNifTerm add(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      term::Term arg0 = term::wrap(argv[0]);
      term::Term arg1 = term::wrap(argv[1]);

      int? a = arg0.get_int(&e);
      if (catch err = a) {
          return term::make_badarg(&e).raw();
      }

      int? b = arg1.get_int(&e);
      if (catch err = b) {
          return term::make_badarg(&e).raw();
      }

      return term::make_int(&e, a + b).raw();
  }
  """

  # Elixir stub - called before NIF loads
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
```

## Understanding the Code

### Module Declaration

```elixir
use C3nif, otp_app: :my_nif_app
```

This sets up the module for NIF compilation. The `:otp_app` option tells C3nif where to find your `priv` directory for loading the compiled NIF.

### Options

| Option | Description |
|--------|-------------|
| `:otp_app` | Required. The OTP application name for finding priv directory |
| `:c3_sources` | Optional. List of external C3 source file paths or glob patterns |

See [External C3 Sources](#external-c3-sources) for more on `:c3_sources`.

### The ~c3 Sigil

The `~c3` sigil contains your C3 code. It will be extracted and compiled during the Mix build process.

### NIF Annotation

```c3
<* nif: arity = 2 *>
```

This annotation marks a function as a NIF. The `arity` specifies how many Elixir arguments it takes.

### NIF Function Signature

Every NIF function has the same signature:

```c3
fn erl_nif::ErlNifTerm function_name(
    erl_nif::ErlNifEnv* raw_env,  // The environment handle
    CInt argc,                      // Number of arguments
    erl_nif::ErlNifTerm* argv       // Array of argument terms
)
```

### Wrapping Raw Types

C3nif provides safe wrappers around the raw NIF API:

```c3
env::Env e = env::wrap(raw_env);           // Wrap the environment
term::Term arg0 = term::wrap(argv[0]);     // Wrap a term
```

### Extracting Values

Use the `get_*` methods to extract Elixir values:

```c3
int? a = arg0.get_int(&e);  // Returns optional int
if (catch err = a) {
    return term::make_badarg(&e).raw();  // Return error on failure
}
```

### Creating Return Values

Use `make_*` functions to create Elixir terms:

```c3
return term::make_int(&e, a + b).raw();
```

### Elixir Stub

```elixir
def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
```

This stub is called if the NIF fails to load. It's required by the Erlang VM.

## Compiling and Running

Compile your project:

```bash
mix compile
```

Try it in IEx:

```bash
iex -S mix
iex> MyNifApp.Math.add(1, 2)
3
iex> MyNifApp.Math.add(100, 200)
300
```

## Error Handling

If you pass invalid arguments:

```elixir
iex> MyNifApp.Math.add("not", "integers")
** (ArgumentError) argument error
```

The `make_badarg` function signals an argument error to the Erlang VM.

## External C3 Sources

For larger projects, you can organize your C3 code in external files instead of embedding everything in the `~c3` sigil. Use the `:c3_sources` option to include additional C3 source files:

```elixir
defmodule MyNifApp.Math do
  use C3nif,
    otp_app: :my_nif_app,
    c3_sources: [
      "c3_src/math_helpers.c3",
      "c3_src/utils/**/*.c3"
    ]

  ~c3"""
  module math;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import math_helpers;  // Import external module

  <* nif: arity = 2 *>
  fn erl_nif::ErlNifTerm multiply(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      // ... use functions from math_helpers ...
  }
  """

  def multiply(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
```

### Path Resolution

- Paths are relative to your project root
- Glob patterns like `**/*.c3` are supported for matching multiple files
- Absolute paths are also supported

### Example Directory Structure

```
my_nif_app/
├── c3_src/
│   ├── math_helpers.c3    # External C3 module
│   └── utils/
│       └── string_utils.c3
├── lib/
│   └── my_nif_app/
│       └── math.ex        # Elixir module with use C3nif
└── mix.exs
```

### Benefits

- **Better organization** - Keep C3 code in dedicated files
- **IDE support** - Use C3 syntax highlighting and tools on `.c3` files
- **Code reuse** - Share C3 modules across multiple NIFs
- **Incremental builds** - Only recompile when source files change

## Next Steps

- Learn about [Type Conversion](type-conversion.md) for all supported types
- See [Error Handling](error-handling.md) for robust error patterns
- Explore [Resource Management](resources.md) for managing native data
- Use [Dirty Schedulers](dirty-schedulers.md) for long-running operations
