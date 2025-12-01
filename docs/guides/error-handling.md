# Error Handling

This guide covers error handling patterns in C3nif to write robust NIFs that don't crash the BEAM VM.

## The Problem

Unlike Elixir, C3 has no exception handling mechanism. Unhandled errors can crash the entire Erlang VM, not just the calling process. C3nif provides patterns to safely handle errors and convert them to Elixir-friendly results.

## C3's Optional Types

C3 uses optional types (suffixed with `?`) for operations that can fail:

```c3
int? value = arg.get_int(&e);  // Returns int or fault
```

### Handling Optionals

Use `if (catch ...)` to handle faults:

```c3
int? value = arg.get_int(&e);
if (catch err = value) {
    // Handle the error - `err` contains the fault
    return term::make_badarg(&e).raw();
}
// Use `value` safely here - it's now unwrapped
```

### Propagating Faults

Use `!` to propagate faults to the caller:

```c3
fn int? add_values(Env* e, Term a, Term b) {
    int val_a = a.get_int(e)!;  // Propagates fault if fails
    int val_b = b.get_int(e)!;
    return val_a + val_b;
}
```

## The Two-Layer NIF Pattern

Every NIF should use this pattern for safety:

```c3
import c3nif::safety;

// INNER function - uses optionals, propagates faults
fn Term? double_impl(Env* e, ErlNifTerm* argv, CInt argc) {
    Term arg = safety::get_arg(argv, argc, 0)!;
    int value = safety::require_int(e, arg)!;
    return term::make_int(e, value * 2);
}

// OUTER function - fault barrier
<* nif: arity = 1 *>
fn ErlNifTerm double_value(
    ErlNifEnv* env_raw,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(env_raw);

    // Catch ALL faults at the boundary
    Term? result = double_impl(&e, argv, argc);
    if (catch fault = result) {
        return term::make_badarg(&e).raw();
    }

    return result.raw();
}
```

### Why Two Layers?

1. **Inner function** - Clean code using `!` for fault propagation
2. **Outer function** - Fault barrier that catches all faults before they reach the BEAM

## Fault Types

C3nif defines several fault types:

### term.c3 Faults
| Fault | Meaning |
|-------|---------|
| `BADARG` | Term is not the expected type |
| `OVERFLOW` | Value doesn't fit in target type |
| `ENCODING` | String encoding error |

### safety.c3 Faults
| Fault | Meaning |
|-------|---------|
| `ALLOC_FAILED` | Memory allocation failure |
| `RESOURCE_ERROR` | Resource extraction failed |
| `ENCODE_ERROR` | Term encoding failed |
| `ARGC_MISMATCH` | Wrong number of arguments |

## Safety Helpers

The `safety` module provides validated extraction helpers:

```c3
import c3nif::safety;

// Validate argument count
safety::require_argc(2, argc)!;

// Safe argument access
Term arg0 = safety::get_arg(argv, argc, 0)!;
Term arg1 = safety::get_arg(argv, argc, 1)!;

// Type-validated extraction
int a = safety::require_int(&e, arg0)!;
int b = safety::require_int(&e, arg1)!;

// Range validation
int positive = safety::require_positive(&e, arg0)!;
int bounded = safety::require_int_range(&e, arg0, 0, 100)!;
int non_neg = safety::require_non_negative(&e, arg0)!;

// Type checking
safety::require_atom(&e, arg0)!;      // Fails if not atom
safety::require_list(&e, arg0)!;      // Fails if not list
safety::require_tuple(&e, arg0)!;     // Fails if not tuple
safety::require_map(&e, arg0)!;       // Fails if not map

// Extract typed values
ErlNifBinary bin = safety::require_binary(&e, arg0)!;
ErlNifPid pid = safety::require_pid(&e, arg0)!;
```

## Return Value Patterns

### Returning Success

```c3
// Simple value
return term::make_int(&e, 42).raw();

// Atom
return term::make_atom(&e, "ok").raw();

// Tuple {:ok, value}
return term::make_ok_tuple(&e, term::make_int(&e, result)).raw();
```

### Returning Errors

```c3
// Raise ArgumentError
return term::make_badarg(&e).raw();

// Return {:error, reason}
return term::make_error_tuple(&e, term::make_atom(&e, "not_found")).raw();

// Shorthand for atom reason
return term::make_error_atom(&e, "invalid_input").raw();
```

### The NifResult Type

For more explicit error handling, use `NifResult`:

```c3
fn NifResult process_data(Env* e, Term arg) {
    int? value = arg.get_int(e);
    if (catch err = value) {
        return safety::badarg(e);
    }

    if (value < 0) {
        return safety::error(e, "negative_not_allowed");
    }

    return safety::ok(term::make_int(e, value * 2));
}

// In the NIF:
NifResult result = process_data(&e, arg);
if (result.is_error) {
    return result.value.raw();
}
return result.value.raw();
```

## Error Conversion Helpers

Convert faults to error tuples:

```c3
Term? result = risky_operation(&e);
if (catch fault = result) {
    // Convert fault to appropriate error
    return safety::make_badarg_error(&e).raw();
    // Or: safety::make_overflow_error(&e).raw()
    // Or: safety::make_alloc_error(&e).raw()
    // Or: safety::make_resource_error(&e).raw()
    // Or: safety::make_unknown_error(&e).raw()
}
```

## What You Cannot Catch

Some errors will still crash the BEAM:

- **Segmentation faults** - Invalid pointer access
- **Stack overflow** - Deep recursion or large stack allocations
- **Unsafe C3 code** - Using `!!` force unwrap, raw pointer arithmetic
- **Integer overflow** - Without trap-on-wrap enabled

### Prevention Strategies

1. **Never use `!!`** - Always handle optionals explicitly
2. **Validate all inputs** - Check types and ranges early
3. **Use bounds checking** - Access arrays safely
4. **Test with sanitizers** - Use AddressSanitizer in CI

## Complete Example

```c3
import c3nif;
import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;
import c3nif::safety;

// Inner implementation - clean, uses fault propagation
fn Term? divide_impl(Env* e, ErlNifTerm* argv, CInt argc) {
    // Validate argument count
    safety::require_argc(2, argc)!;

    // Extract arguments safely
    Term arg0 = safety::get_arg(argv, argc, 0)!;
    Term arg1 = safety::get_arg(argv, argc, 1)!;

    int numerator = safety::require_int(e, arg0)!;
    int denominator = safety::require_int(e, arg1)!;

    // Business logic validation
    if (denominator == 0) {
        return term::BADARG?;  // Return fault for division by zero
    }

    return term::make_int(e, numerator / denominator);
}

// Outer NIF - fault barrier
<* nif: arity = 2 *>
fn ErlNifTerm divide(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    Term? result = divide_impl(&e, argv, argc);
    if (catch fault = result) {
        // All faults become badarg - or use more specific handling
        return term::make_badarg(&e).raw();
    }

    return result.raw();
}
```

## Best Practices

1. **Always use the two-layer pattern** - Inner implementation, outer fault barrier

2. **Validate early** - Check argument count and types at the start

3. **Use safety helpers** - They provide consistent error handling

4. **Return meaningful errors** - Use `{:error, reason}` tuples when appropriate

5. **Document error conditions** - Tell users what can fail and why

6. **Test error paths** - Ensure invalid inputs return errors, not crashes
