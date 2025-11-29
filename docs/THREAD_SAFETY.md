# Thread-Safety Guide for c3nif

This document describes thread-safety considerations when writing NIFs with c3nif, particularly when using dirty schedulers or async operations.

## Overview

The BEAM VM uses a scheduler-per-core model. Normal NIFs run on regular schedulers and must complete quickly (< 1ms). Dirty schedulers allow longer-running operations without blocking the VM. Understanding which operations are thread-safe is critical for correct NIF implementation.

## Safe Operations

The following operations are thread-safe and can be called from any scheduler, including dirty schedulers:

### Memory Allocation

| Function | Thread-Safe | Notes |
|----------|-------------|-------|
| `enif_alloc` | ✅ Yes | General memory allocation |
| `enif_free` | ✅ Yes | Must match `enif_alloc` |
| `enif_realloc` | ✅ Yes | Resize allocation |

### Resource Operations

| Function | Thread-Safe | Notes |
|----------|-------------|-------|
| `enif_alloc_resource` | ✅ Yes | Allocate a new resource |
| `enif_keep_resource` | ✅ Yes | Atomic reference count increment |
| `enif_release_resource` | ✅ Yes | Atomic reference count decrement |
| `enif_make_resource` | ✅ Yes | Convert resource to term |
| `enif_get_resource` | ✅ Yes | Extract resource from term |

### Process Monitoring

| Function | Thread-Safe | Notes |
|----------|-------------|-------|
| `enif_monitor_process` | ✅ Yes | Designed for async/dirty use |
| `enif_demonitor_process` | ✅ Yes | Safe to call concurrently |
| `enif_compare_monitors` | ✅ Yes | Pure comparison, no state |

### Message Passing

| Function | Thread-Safe | Notes |
|----------|-------------|-------|
| `enif_send` | ✅ Yes | Primary async communication method |
| `enif_alloc_env` | ✅ Yes | Create independent environment |
| `enif_free_env` | ✅ Yes | Free independent environment |

### Binary Operations

| Function | Thread-Safe | Notes |
|----------|-------------|-------|
| `enif_alloc_binary` | ✅ Yes | Allocate new binary |
| `enif_release_binary` | ✅ Yes | Release binary memory |
| `enif_realloc_binary` | ✅ Yes | Resize binary |

## Registration (on_load only)

These operations are **only safe during module loading**:

| Function | When Safe | Notes |
|----------|-----------|-------|
| `resource::register_type()` | on_load only | Single-threaded context |
| `resource::register_type_full()` | on_load only | Single-threaded context |
| Module-level globals write | on_load only | No synchronization needed |

After `on_load` completes:
- The resource type registry becomes immutable
- Read access to registered types is safe from any scheduler
- Module globals should be treated as read-only

## Resource State

**Your resource contents are NOT automatically thread-safe.**

When a resource may be accessed from multiple schedulers (e.g., dirty schedulers, async callbacks), you must add synchronization:

### Options for Thread-Safe Resource State

1. **Atomics** - Best for simple counters and flags
   ```c3
   struct MyResource {
       std::atomic::Atomic!int counter;  // Thread-safe counter
   }
   ```

2. **Mutexes** - For complex state modifications
   ```c3
   struct MyResource {
       Mutex lock;
       ComplexState state;
   }
   ```

3. **Message Passing** - Often the best approach
   - Keep mutable state in a single process
   - Use `enif_send` to communicate results
   - Avoids shared mutable state entirely

### Example: Thread-Safe Counter

```c3
struct Counter {
    std::atomic::Atomic!int value;
}

fn void increment(Counter* c) {
    c.value.fetch_add(1, .seq_cst);
}

fn int get(Counter* c) {
    return c.value.load(.seq_cst);
}
```

## Callback Thread-Safety

### Destructor Callbacks (dtor)

Destructor callbacks have special constraints:

| Aspect | Details |
|--------|---------|
| When called | When resource refcount reaches zero (during GC) |
| Which thread | Arbitrary scheduler thread (may be dirty) |
| Timing | Non-deterministic |

**Safe operations in destructors:**
- `enif_alloc` / `enif_free`
- `enif_send` (with `enif_alloc_env`)
- `enif_release_resource` (for nested resources)

**Unsafe operations in destructors:**
- `enif_self` - No calling process
- Creating terms with the destructor's env
- Blocking operations

**Example: Sending notification from destructor**

```c3
fn void my_dtor(ErlNifEnv* env_raw, void* obj) {
    MyResource* r = (MyResource*)obj;

    // Create independent environment for message
    ErlNifEnv* msg_env = enif_alloc_env();
    if (msg_env == null) return;

    // Build message in the new environment
    ErlNifTerm msg = enif_make_atom(msg_env, "resource_destroyed");

    // Send to stored PID
    enif_send(null, &r.notify_pid, msg_env, msg);

    // Free the message environment
    enif_free_env(msg_env);
}
```

### Down Callbacks (process monitoring)

Down callbacks fire when a monitored process terminates:

| Aspect | Details |
|--------|---------|
| When called | Immediately when monitored process dies |
| Which thread | Scheduler that detects the death |
| Monitor state | Automatically removed after callback |

**Requirements:**
- Resource type must be registered with `.members >= 3` in `ErlNifResourceTypeInit`
- Use `resource::register_type_full()` to enable down callbacks

**Safe operations in down callbacks:**
- Most `enif_*` functions
- `enif_send` for notifications
- Resource cleanup operations

**Example: Down callback with notification**

```c3
fn void my_down(
    ErlNifEnv* env_raw,
    void* obj,
    ErlNifPid* dead_pid,
    ErlNifMonitor* monitor
) {
    MyResource* r = (MyResource*)obj;

    // Create message environment
    ErlNifEnv* msg_env = enif_alloc_env();
    if (msg_env == null) return;

    // Build {:process_down, pid} tuple
    ErlNifTerm atom = enif_make_atom(msg_env, "process_down");
    ErlNifTerm pid_term = erl_nif::make_pid(msg_env, dead_pid);
    ErlNifTerm[2] elems = { atom, pid_term };
    ErlNifTerm msg = enif_make_tuple_from_array(msg_env, &elems, 2);

    // Notify observer
    enif_send(null, &r.observer_pid, msg_env, msg);

    enif_free_env(msg_env);
}
```

## Dirty Scheduler Restrictions

When running on dirty schedulers, some operations are restricted:

| Operation | Available | Notes |
|-----------|-----------|-------|
| `enif_self` | ❌ No | Returns NULL on dirty schedulers |
| `enif_send` | ✅ Yes | Use NULL for caller_env |
| Term creation | ⚠️ Limited | Use `enif_alloc_env` for messages |
| Process dictionary | ❌ No | Not accessible |
| Receive messages | ❌ No | Not possible |

## Best Practices

1. **Prefer message passing over shared state**
   - Send results to processes via `enif_send`
   - Let BEAM handle synchronization

2. **Keep destructors fast and non-blocking**
   - Defer heavy cleanup to a dedicated process
   - Send a message and let a process handle it

3. **Use appropriate synchronization**
   - Atomics for simple counters
   - Avoid locks if possible (deadlock risk)

4. **Initialize everything in on_load**
   - Resource types
   - Module-level state
   - Configuration

5. **Don't store term references beyond their environment's lifetime**
   - Terms are only valid within their environment
   - Copy to a new environment if needed for async use

## Common Patterns

### Async Operation with Callback

```c3
// 1. Store caller PID and result destination
struct AsyncOp {
    ErlNifPid caller;
    ErlNifEnv* result_env;  // For building result
}

// 2. In dirty NIF, perform work and send result
fn void do_async_work(AsyncOp* op) {
    // ... do expensive work ...

    ErlNifTerm result = build_result(op.result_env);
    enif_send(null, &op.caller, op.result_env, result);

    enif_free_env(op.result_env);
}
```

### Resource with Process Monitor

```c3
// Resource tracks a process and cleans up when it dies
struct TrackedResource {
    ErlNifPid owner;
    ErlNifMonitor monitor;
    // ... resource data ...
}

// Register with down callback enabled
ErlNifResourceTypeInit init = {
    .dtor = &tracked_dtor,
    .stop = null,
    .down = &tracked_down,
    .members = 3,  // Required for down callback
    .dyncall = null
};
resource::register_type_full(&e, "TrackedResource", &init);
```

## Further Reading

- [Erlang NIF documentation](https://www.erlang.org/doc/man/erl_nif)
- [Dirty NIF documentation](https://www.erlang.org/doc/man/erl_nif#dirty_nifs)
- [c3nif resource.c3](../c3nif.c3l/resource.c3) - Implementation with inline docs
