# Type Conversion

This guide covers all supported type conversions between Elixir and C3.

## Conversion Overview

| Elixir Type | C3 Type | Make Function | Get Method |
|-------------|---------|---------------|------------|
| `integer()` | `int` | `make_int/2` | `Term.get_int/1` |
| `integer()` | `uint` | `make_uint/2` | `Term.get_uint/1` |
| `integer()` | `long` | `make_long/2` | `Term.get_long/1` |
| `integer()` | `ulong` | `make_ulong/2` | `Term.get_ulong/1` |
| `float()` | `double` | `make_double/2` | `Term.get_double/1` |
| `atom()` | `char*` | `make_atom/2` | `Term.get_atom_length/1` |
| `binary()` | `ErlNifBinary` | `make_new_binary/3` | `Term.inspect_binary/1` |
| `list()` | `ErlNifTerm[]` | `make_list_from_array/2` | `Term.get_list_cell/3` |
| `tuple()` | `ErlNifTerm[]` | `make_tuple_from_array/2` | `Term.get_tuple/2` |
| `map()` | - | `make_new_map/1` | `Term.map_get/2` |
| `reference()` | - | `make_ref/1` | `Term.is_ref/1` |
| `pid()` | `ErlNifPid` | - | `Term.get_local_pid/1` |

## Integers

### Creating Integers

```c3
import c3nif::term;

// Signed integers
Term result = term::make_int(&e, 42);
Term result = term::make_long(&e, 9223372036854775807);

// Unsigned integers
Term result = term::make_uint(&e, 4294967295);
Term result = term::make_ulong(&e, 18446744073709551615);
```

### Extracting Integers

All extraction methods return optionals (`?` types) that fail with `BADARG` if the term is not the expected type:

```c3
Term arg = term::wrap(argv[0]);

// Extract signed int
int? value = arg.get_int(&e);
if (catch err = value) {
    return term::make_badarg(&e).raw();
}
// Use value safely here

// Extract long (for larger values)
long? big_value = arg.get_long(&e);
```

### Integer Ranges

| Type | Min | Max |
|------|-----|-----|
| `int` | -2,147,483,648 | 2,147,483,647 |
| `uint` | 0 | 4,294,967,295 |
| `long` | -9,223,372,036,854,775,808 | 9,223,372,036,854,775,807 |
| `ulong` | 0 | 18,446,744,073,709,551,615 |

Values outside these ranges will fail extraction with `BADARG`.

## Floats

### Creating Floats

```c3
Term result = term::make_double(&e, 3.14159);
Term result = term::make_double(&e, -273.15);
```

### Extracting Floats

```c3
double? value = arg.get_double(&e);
if (catch err = value) {
    return term::make_badarg(&e).raw();
}
```

Note: Elixir integers are NOT automatically converted to floats. `1` and `1.0` are different types.

## Atoms

### Creating Atoms

```c3
// From null-terminated string
Term ok = term::make_atom(&e, "ok");
Term error = term::make_atom(&e, "error");
Term custom = term::make_atom(&e, "my_custom_atom");

// From string with length
Term atom = term::make_atom_len(&e, "hello", 5);
```

**Warning**: `make_atom` creates atoms unconditionally. Atoms are not garbage collected, so creating atoms from user input can exhaust the atom table. Use `make_existing_atom` for user input:

```c3
// Safe for user input - only succeeds if atom exists
Term? atom = term::make_existing_atom(&e, user_string);
if (catch err = atom) {
    return term::make_badarg(&e).raw();  // Unknown atom
}
```

### Checking Atoms

```c3
if (arg.is_atom(&e)) {
    // It's an atom
}

// Get atom length (to allocate buffer for reading)
uint? len = arg.get_atom_length(&e);
```

## Binaries

Binaries are the most efficient way to pass byte data between Elixir and C3.

### Inspecting Binaries (Zero-Copy)

```c3
import c3nif::binary;

// Get read-only access to binary data
Binary? bin = binary::inspect(&e, arg);
if (catch err = bin) {
    return term::make_badarg(&e).raw();
}

// Access data
char[] data = bin.as_slice();
usz size = bin.size;

// Process the data (read-only)
for (usz i = 0; i < size; i++) {
    char byte = data[i];
    // ...
}
```

### Creating Binaries

```c3
// Create a new binary with allocated space
char* data;
Term result = term::make_new_binary(&e, 100, &data);

// Write data into the buffer
for (usz i = 0; i < 100; i++) {
    data[i] = (char)i;
}

// Return the binary
return result.raw();
```

### Creating from Existing Data

```c3
// From a slice
char[] my_data = "Hello, World!";
Term result = binary::from_slice(&e, my_data);

// Copy existing data
Binary source = /* ... */;
Term copy = binary::copy(&e, &source);
```

### Sub-binaries (Views)

Sub-binaries share memory with the parent:

```c3
// Create a view into an existing binary
Term sub = term::make_sub_binary(&e, parent_term, offset, length);
```

### Binary Size Thresholds

- **Heap binaries** (< 64 bytes): Copied on the process heap
- **Reference-counted binaries** (>= 64 bytes): Shared, reference counted

For large binaries, use `binary::alloc` for reference-counted allocation:

```c3
Binary? bin = binary::alloc(1024 * 1024);  // 1MB
if (catch err = bin) {
    return term::make_badarg(&e).raw();
}
// ... fill data ...
Term result = binary::make_new(&e, &bin);
```

## Lists

### Creating Lists

```c3
// Empty list
Term empty = term::make_empty_list(&e);

// From array
ErlNifTerm[3] items = {
    term::make_int(&e, 1).raw(),
    term::make_int(&e, 2).raw(),
    term::make_int(&e, 3).raw()
};
Term list = term::make_list_from_array(&e, items[0:3]);

// Build list incrementally (prepend - efficient)
Term list = term::make_empty_list(&e);
list = term::make_list_cell(&e, term::make_int(&e, 3), list);
list = term::make_list_cell(&e, term::make_int(&e, 2), list);
list = term::make_list_cell(&e, term::make_int(&e, 1), list);
// Result: [1, 2, 3]
```

### Iterating Lists

```c3
Term head;
Term tail = arg;  // The list term

while (!tail.is_empty_list(&e)) {
    if (tail.get_list_cell(&e, &head, &tail)) |_| {
        // Error - not a proper list
        return term::make_badarg(&e).raw();
    }

    // Process head
    int? value = head.get_int(&e);
    // ...
}
```

### List Length

```c3
uint? len = arg.get_list_length(&e);
if (catch err = len) {
    return term::make_badarg(&e).raw();  // Not a proper list
}
```

## Tuples

### Creating Tuples

```c3
// From array
ErlNifTerm[2] elements = {
    term::make_atom(&e, "ok").raw(),
    term::make_int(&e, 42).raw()
};
Term tuple = term::make_tuple_from_array(&e, elements[0:2]);
// Result: {:ok, 42}
```

### Extracting Tuples

```c3
ErlNifTerm* elements;
int? arity = arg.get_tuple(&e, &elements);
if (catch err = arity) {
    return term::make_badarg(&e).raw();
}

// Access elements
if (arity == 2) {
    Term first = term::wrap(elements[0]);
    Term second = term::wrap(elements[1]);
    // ...
}
```

### Common Tuple Patterns

```c3
// Create {:ok, value}
Term result = term::make_ok_tuple(&e, value);

// Create {:error, reason}
Term result = term::make_error_tuple(&e, term::make_atom(&e, "invalid"));

// Shorthand for error atoms
Term result = term::make_error_atom(&e, "not_found");
```

## Maps

### Creating Maps

```c3
// Empty map
Term map = term::make_new_map(&e);

// Add entries
Term? map2 = map.map_put(&e, term::make_atom(&e, "name"), term::make_atom(&e, "alice"));
if (catch err = map2) {
    return term::make_badarg(&e).raw();
}

Term? map3 = map2.map_put(&e, term::make_atom(&e, "age"), term::make_int(&e, 30));
```

### Reading Maps

```c3
// Get value by key
Term key = term::make_atom(&e, "name");
Term? value = arg.map_get(&e, key);
if (catch err = value) {
    // Key not found
}

// Get map size
usz? size = arg.get_map_size(&e);
```

## PIDs

### Extracting PIDs

```c3
erl_nif::ErlNifPid? pid = arg.get_local_pid(&e);
if (catch err = pid) {
    return term::make_badarg(&e).raw();
}

// Use PID for sending messages, monitoring, etc.
```

### Checking PIDs

```c3
if (arg.is_pid(&e)) {
    // It's a PID
}
```

## References

### Creating References

```c3
Term ref = term::make_ref(&e);  // Unique reference
```

### Checking References

```c3
if (arg.is_ref(&e)) {
    // It's a reference
}
```

## Type Checking

Before extraction, you can check term types:

```c3
if (arg.is_atom(&e)) { /* ... */ }
if (arg.is_binary(&e)) { /* ... */ }
if (arg.is_list(&e)) { /* ... */ }
if (arg.is_tuple(&e)) { /* ... */ }
if (arg.is_map(&e)) { /* ... */ }
if (arg.is_number(&e)) { /* ... */ }
if (arg.is_pid(&e)) { /* ... */ }
if (arg.is_ref(&e)) { /* ... */ }
if (arg.is_fun(&e)) { /* ... */ }
if (arg.is_port(&e)) { /* ... */ }
if (arg.is_empty_list(&e)) { /* ... */ }
```

## Term Comparison

```c3
// Identity check
if (term1 == term2) {
    // Same term (identical)
}

// Ordering comparison
int cmp = term1.compare_to(term2);
if (cmp < 0) { /* term1 < term2 */ }
if (cmp == 0) { /* term1 == term2 */ }
if (cmp > 0) { /* term1 > term2 */ }
```

## Best Practices

1. **Always handle extraction failures** - Use the `?` optional pattern and `catch`

2. **Use appropriate integer sizes** - `int` for small values, `long` for large ones

3. **Avoid creating atoms from user input** - Use `make_existing_atom` instead

4. **Use binaries for byte data** - More efficient than charlists

5. **Build lists by prepending** - `make_list_cell` is O(1), appending is O(n)

6. **Check types before extraction** - Use `is_*` methods for defensive coding
