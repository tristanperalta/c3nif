# Resource Management

This guide covers NIF resources - native data structures managed by the BEAM's garbage collector.

## What Are Resources?

Resources are reference-counted native memory blocks that:

- Are garbage collected by the BEAM VM
- Can have destructor callbacks for cleanup
- Are opaque to Elixir code (cannot be inspected)
- Are type-safe (each resource has a registered type)

Use resources when you need to:
- Store native data structures across NIF calls
- Wrap handles to external libraries (file handles, network connections)
- Manage memory that requires cleanup

## Basic Usage

### 1. Register the Resource Type

Resource types must be registered in your `on_load` callback:

```c3
import c3nif::resource;

erl_nif::ErlNifResourceType* g_my_resource_type;

fn CInt on_load(
    ErlNifEnv* raw_env,
    void** priv,
    ErlNifTerm load_info
) {
    Env e = env::wrap(raw_env);

    erl_nif::ErlNifResourceType*? rt = resource::register_type(
        &e,
        "MyResource",
        &my_resource_destructor
    );

    if (catch err = rt) {
        return 1;  // Failed
    }

    g_my_resource_type = rt;
    return 0;  // Success
}
```

### 2. Define Your Data Structure

```c3
struct MyData {
    int value;
    char* name;
    bool initialized;
}
```

### 3. Define the Destructor

```c3
fn void my_resource_destructor(
    ErlNifEnv* env,
    void* obj
) {
    MyData* data = (MyData*)obj;

    // Cleanup any allocated memory
    if (data.name != null) {
        allocator::free(data.name);
    }

    // The resource memory itself is freed automatically
}
```

### 4. Create Resources

```c3
<* nif: arity = 1 *>
fn ErlNifTerm create_resource(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);
    Term arg = term::wrap(argv[0]);

    int? value = arg.get_int(&e);
    if (catch err = value) {
        return term::make_badarg(&e).raw();
    }

    // Allocate the resource
    void*? ptr = resource::alloc("MyResource", MyData.sizeof);
    if (catch err = ptr) {
        return term::make_error_atom(&e, "alloc_failed").raw();
    }

    // Initialize the data
    MyData* data = (MyData*)ptr;
    data.value = value;
    data.name = null;
    data.initialized = true;

    // Create term and release our reference
    Term result = resource::make_term(&e, ptr);
    resource::release(ptr);  // Term now owns the reference

    return result.raw();
}
```

### 5. Access Resources

```c3
<* nif: arity = 1 *>
fn ErlNifTerm get_value(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);
    Term arg = term::wrap(argv[0]);

    // Extract the resource
    void*? ptr = resource::get("MyResource", &e, arg);
    if (catch err = ptr) {
        return term::make_badarg(&e).raw();
    }

    MyData* data = (MyData*)ptr;
    return term::make_int(&e, data.value).raw();
}
```

## Reference Counting

Resources use reference counting for lifetime management:

| Operation | Effect |
|-----------|--------|
| `alloc()` | Creates resource with ref count = 1 |
| `make_term()` | Increments ref count (+1) |
| `release()` | Decrements ref count (-1) |
| `keep()` | Increments ref count (+1) |

### Standard Pattern

```c3
// Allocate (ref count = 1)
void* ptr = resource::alloc("MyType", size)!;

// Initialize...
MyStruct* data = (MyStruct*)ptr;
data.field = value;

// Create term (ref count = 2)
Term t = resource::make_term(&e, ptr);

// Release our reference (ref count = 1, term owns it)
resource::release(ptr);

// Return the term
return t.raw();
```

### Keeping References in Native Code

If you need to store a resource pointer that survives beyond the NIF call:

```c3
// Store resource pointer in native storage
void* ptr = resource::get("MyType", &e, arg)!;
resource::keep(ptr);  // Increment ref count
g_my_global_ptr = ptr;  // Now safe to store

// Later, when done:
resource::release(g_my_global_ptr);  // Decrement ref count
g_my_global_ptr = null;
```

## Destructor Callbacks

Destructors are called when the resource's reference count reaches zero:

```c3
fn void my_destructor(ErlNifEnv* env, void* obj) {
    MyData* data = (MyData*)obj;

    // Free any nested allocations
    if (data.buffer != null) {
        allocator::free(data.buffer);
    }

    // Close any handles
    if (data.file_handle != null) {
        close_file(data.file_handle);
    }

    // The resource memory itself is freed automatically by the BEAM
}
```

### Destructor Rules

1. **Timing is non-deterministic** - Depends on garbage collection
2. **Runs on arbitrary scheduler** - Could be any thread
3. **Keep it fast** - Don't block or do heavy computation
4. **Limited env** - Can't create terms with the destructor's env
5. **Can send messages** - Use `enif_alloc_env()` for message construction

### Sending Messages from Destructors

```c3
fn void cleanup_destructor(ErlNifEnv* env, void* obj) {
    MyData* data = (MyData*)obj;

    if (data.notify_pid_valid) {
        // Create a private environment for the message
        ErlNifEnv* msg_env = erl_nif::enif_alloc_env();

        // Build message in the private environment
        Env e = env::wrap(msg_env);
        Term msg = term::make_tuple_from_array(&e, (ErlNifTerm[2]){
            term::make_atom(&e, "resource_destroyed").raw(),
            term::make_int(&e, data.id).raw()
        }[0:2]);

        // Send the message
        erl_nif::enif_send(null, &data.notify_pid, msg_env, msg.raw());

        // Free the private environment
        erl_nif::enif_free_env(msg_env);
    }
}
```

## Process Monitoring

Resources can monitor Erlang processes and receive callbacks when they die:

### Registration with Down Callback

```c3
fn void my_down_callback(
    ErlNifEnv* env,
    void* obj,
    erl_nif::ErlNifPid* pid,
    erl_nif::ErlNifMonitor* monitor
) {
    MyData* data = (MyData*)obj;
    // Handle the process death
    data.owner_alive = false;
}

fn CInt on_load(ErlNifEnv* raw_env, void** priv, ErlNifTerm load_info) {
    Env e = env::wrap(raw_env);

    // Use register_type_full for down callback support
    erl_nif::ErlNifResourceTypeInit init = {
        .dtor = &my_destructor,
        .stop = null,
        .down = &my_down_callback,
        .members = 3,  // Must be >= 3 for down callback
        .dyncall = null
    };

    erl_nif::ErlNifResourceType*? rt = resource::register_type_full(
        &e,
        "MonitoredResource",
        &init
    );

    // ...
}
```

### Setting Up a Monitor

```c3
<* nif: arity = 2 *>
fn ErlNifTerm monitor_owner(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    void* ptr = resource::get("MonitoredResource", &e, term::wrap(argv[0]))!;
    erl_nif::ErlNifPid? owner_pid = term::wrap(argv[1]).get_local_pid(&e);
    if (catch err = owner_pid) {
        return term::make_badarg(&e).raw();
    }

    MyData* data = (MyData*)ptr;

    // Start monitoring the process
    if (!resource::monitor_process(&e, ptr, &owner_pid, &data.monitor)) {
        return term::make_error_atom(&e, "monitor_failed").raw();
    }

    data.owner_pid = owner_pid;
    data.owner_alive = true;

    return term::make_atom(&e, "ok").raw();
}
```

### Canceling a Monitor

```c3
// In NIF:
if (!resource::demonitor_process(&e, ptr, &data.monitor)) {
    // Already triggered or invalid
}
```

## Thread Safety

### Safe Operations (Any Thread)

- `resource::alloc()` / `resource::release()` / `resource::keep()`
- `resource::monitor_process()` / `resource::demonitor_process()`
- Reading immutable resource fields

### Unsafe Without Synchronization

- Modifying resource fields from multiple threads
- Reading mutable fields while another thread writes

### Synchronization Strategies

For mutable resource state:

```c3
struct ThreadSafeData {
    // Use atomics for simple values
    int counter;  // Access with atomic operations

    // Or use a mutex for complex state
    // (requires platform-specific implementation)
}

// Atomic increment example
fn void increment_counter(ThreadSafeData* data) {
    // Use C3's atomic intrinsics
    @atomic_add(&data.counter, 1);
}
```

## Complete Example

```c3
module counter_resource;

import c3nif;
import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;
import c3nif::resource;

struct Counter {
    int value;
}

erl_nif::ErlNifResourceType* g_counter_type;

fn void counter_destructor(ErlNifEnv* env, void* obj) {
    // Nothing to clean up for this simple struct
}

fn CInt on_load(ErlNifEnv* raw_env, void** priv, ErlNifTerm load_info) {
    Env e = env::wrap(raw_env);

    erl_nif::ErlNifResourceType*? rt = resource::register_type(
        &e,
        "Counter",
        &counter_destructor
    );

    if (catch err = rt) {
        return 1;
    }

    g_counter_type = rt;
    return 0;
}

<* nif: arity = 1 *>
fn ErlNifTerm new_counter(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    int? initial = term::wrap(argv[0]).get_int(&e);
    if (catch err = initial) {
        return term::make_badarg(&e).raw();
    }

    void*? ptr = resource::alloc("Counter", Counter.sizeof);
    if (catch err = ptr) {
        return term::make_error_atom(&e, "alloc_failed").raw();
    }

    Counter* counter = (Counter*)ptr;
    counter.value = initial;

    Term result = resource::make_term(&e, ptr);
    resource::release(ptr);

    return result.raw();
}

<* nif: arity = 1 *>
fn ErlNifTerm get_counter(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    void*? ptr = resource::get("Counter", &e, term::wrap(argv[0]));
    if (catch err = ptr) {
        return term::make_badarg(&e).raw();
    }

    Counter* counter = (Counter*)ptr;
    return term::make_int(&e, counter.value).raw();
}

<* nif: arity = 2 *>
fn ErlNifTerm increment_counter(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    void*? ptr = resource::get("Counter", &e, term::wrap(argv[0]));
    if (catch err = ptr) {
        return term::make_badarg(&e).raw();
    }

    int? amount = term::wrap(argv[1]).get_int(&e);
    if (catch err = amount) {
        return term::make_badarg(&e).raw();
    }

    Counter* counter = (Counter*)ptr;
    counter.value += amount;

    return term::make_int(&e, counter.value).raw();
}
```

Elixir usage:

```elixir
counter = MyApp.Counter.new_counter(0)
MyApp.Counter.increment_counter(counter, 5)
MyApp.Counter.get_counter(counter)  # => 5
```

## Best Practices

1. **Always release after make_term** - Prevents memory leaks

2. **Initialize all fields** - Destructors may be called on partially initialized resources

3. **Check for null in destructors** - Handle cleanup of optional fields safely

4. **Use process monitors for cleanup** - Don't rely solely on GC timing

5. **Keep destructors fast** - Heavy cleanup should be done in a dedicated process

6. **Document thread safety** - Be explicit about what's safe to call concurrently
