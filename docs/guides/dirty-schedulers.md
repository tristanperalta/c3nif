# Dirty Schedulers

This guide covers dirty schedulers and long-running NIF operations in C3nif.

## The 1ms Rule

Regular NIFs must complete quickly (typically under 1 millisecond) to avoid blocking the Erlang scheduler. The BEAM runs multiple Erlang processes on a fixed number of scheduler threads, and a long-running NIF blocks one of those threads.

**Problem**: A NIF that takes 100ms blocks ~100 other process reductions from happening.

**Solutions**:
1. **Dirty schedulers** - Run on separate thread pools
2. **Yielding NIFs** - Split work into chunks
3. **Async threads** - Run work in a separate thread and send result

## Dirty Scheduler Types

The BEAM provides two dirty scheduler pools:

| Type | Use Case | Pool Size |
|------|----------|-----------|
| CPU-bound | Compute-intensive work (crypto, compression, ML) | Usually = CPU cores |
| I/O-bound | Blocking I/O (file ops, network, syscalls) | Usually = 10 |

## Static Dirty NIF Declaration

The simplest approach: declare the NIF as dirty at compile time:

```c3
<* nif: arity = 1, dirty = cpu *>
fn ErlNifTerm heavy_compute(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);
    // This always runs on a dirty CPU scheduler
    // ...expensive computation...
    return term::make_int(&e, result).raw();
}

<* nif: arity = 1, dirty = io *>
fn ErlNifTerm blocking_io(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);
    // This always runs on a dirty I/O scheduler
    // ...blocking I/O operation...
    return term::make_int(&e, result).raw();
}
```

### Annotation Options

| Annotation | Scheduler Type |
|------------|----------------|
| `dirty = cpu` | Dirty CPU-bound scheduler |
| `dirty = io` | Dirty I/O-bound scheduler |
| (none) | Normal scheduler |

## Dynamic Scheduling

Sometimes you want to decide at runtime whether to use a dirty scheduler:

```c3
import c3nif::scheduler;

<* nif: arity = 1 *>
fn ErlNifTerm process_data(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);
    Term arg = term::wrap(argv[0]);

    // Check data size
    erl_nif::ErlNifBinary? bin = arg.inspect_binary(&e);
    if (catch err = bin) {
        return term::make_badarg(&e).raw();
    }

    if (bin.size > 1024 * 1024) {
        // Large data - schedule on dirty CPU
        return scheduler::schedule_dirty_cpu(
            &e,
            "process_data_impl",
            &process_data_impl,
            argc,
            argv
        ).raw();
    }

    // Small data - process directly
    return do_process(&e, &bin).raw();
}
```

### schedule_nif Variants

```c3
// Schedule on dirty CPU scheduler
scheduler::schedule_dirty_cpu(&e, "name", &func, argc, argv)

// Schedule on dirty I/O scheduler
scheduler::schedule_dirty_io(&e, "name", &func, argc, argv)

// Schedule on normal scheduler (switch back from dirty)
scheduler::schedule_normal(&e, "name", &func, argc, argv)

// Generic with flags
scheduler::schedule_nif(&e, "name", flags, &func, argc, argv)
// where flags is: SCHED_NORMAL, SCHED_CPU_BOUND, or SCHED_IO_BOUND
```

## Thread Type Detection

Check which scheduler type you're running on:

```c3
import c3nif::scheduler;

<* nif: arity = 0 *>
fn ErlNifTerm get_scheduler_type(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    ThreadType t = scheduler::current_thread_type();

    char* name;
    switch (t) {
        case ThreadType.NORMAL:
            name = "normal";
        case ThreadType.DIRTY_CPU:
            name = "dirty_cpu";
        case ThreadType.DIRTY_IO:
            name = "dirty_io";
        default:
            name = "undefined";
    }

    return term::make_atom(&e, name).raw();
}
```

### Helper Functions

```c3
// Check if on dirty scheduler
if (scheduler::is_dirty_scheduler()) {
    // Running on dirty CPU or I/O scheduler
}

// Check if on normal scheduler
if (scheduler::is_normal_scheduler()) {
    // Running on normal scheduler
}
```

## Process Liveness

On dirty schedulers, the calling process can terminate while the NIF runs:

```c3
<* nif: arity = 1, dirty = cpu *>
fn ErlNifTerm long_computation(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    for (int i = 0; i < 1000000; i++) {
        // Periodically check if process is still alive
        if (i % 10000 == 0) {
            if (!scheduler::is_process_alive(&e)) {
                // Process terminated - abort early
                return term::make_atom(&e, "process_terminated").raw();
            }
        }

        // ... do work ...
    }

    return term::make_int(&e, result).raw();
}
```

### What Happens When a Process Dies

When the calling process terminates during a dirty NIF:
1. Links and monitors are triggered
2. The registered name is released
3. ETS tables are cleaned up
4. **The NIF continues to execute**

Always check `is_process_alive()` in long-running dirty NIFs to avoid wasted work.

## Timeslice Consumption

For normal schedulers, consume timeslices to cooperate with the scheduler:

```c3
fn ErlNifTerm cooperative_nif(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    for (int i = 0; i < iterations; i++) {
        // Do a chunk of work
        process_chunk(i);

        // Report progress (1% per chunk)
        if (e.consume_timeslice(1)) {
            // Consumed too much time - should yield
            // For yielding NIFs, schedule continuation here
            break;
        }
    }

    return term::make_int(&e, result).raw();
}
```

The argument to `consume_timeslice` is a percentage (1-100) of a timeslice.
Returns `true` if the NIF has consumed enough time that it should yield.

## Yielding NIFs

For operations that can be split into chunks, yielding NIFs are preferred over dirty schedulers:

```c3
// Context stored in a resource (survives across yields)
struct ComputeContext {
    int current_index;
    int total;
    int result;
}

<* nif: arity = 1 *>
fn ErlNifTerm start_compute(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    int? total = term::wrap(argv[0]).get_int(&e);
    if (catch err = total) {
        return term::make_badarg(&e).raw();
    }

    // Allocate context resource
    void*? ptr = resource::alloc("ComputeContext", ComputeContext.sizeof);
    if (catch err = ptr) {
        return term::make_error_atom(&e, "alloc_failed").raw();
    }

    ComputeContext* ctx = (ComputeContext*)ptr;
    ctx.current_index = 0;
    ctx.total = total;
    ctx.result = 0;

    // Create resource term
    Term ctx_term = resource::make_term(&e, ptr);
    resource::release(ptr);

    // Schedule the continuation with context as argument
    ErlNifTerm[1] new_argv = { ctx_term.raw() };
    return scheduler::schedule_normal(
        &e,
        "compute_chunk",
        &compute_chunk,
        1,
        &new_argv[0]
    ).raw();
}

fn ErlNifTerm compute_chunk(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    void*? ptr = resource::get("ComputeContext", &e, term::wrap(argv[0]));
    if (catch err = ptr) {
        return term::make_badarg(&e).raw();
    }

    ComputeContext* ctx = (ComputeContext*)ptr;

    // Process a chunk
    int chunk_size = 1000;
    int end = ctx.current_index + chunk_size;
    if (end > ctx.total) {
        end = ctx.total;
    }

    for (int i = ctx.current_index; i < end; i++) {
        ctx.result += expensive_operation(i);

        // Optionally check timeslice
        if (i % 100 == 0 && e.consume_timeslice(1)) {
            ctx.current_index = i + 1;
            // Yield and continue later
            return scheduler::schedule_normal(
                &e,
                "compute_chunk",
                &compute_chunk,
                argc,
                argv
            ).raw();
        }
    }

    ctx.current_index = end;

    if (ctx.current_index < ctx.total) {
        // More work to do - yield
        return scheduler::schedule_normal(
            &e,
            "compute_chunk",
            &compute_chunk,
            argc,
            argv
        ).raw();
    }

    // Done - return result
    return term::make_int(&e, ctx.result).raw();
}
```

## Choosing the Right Approach

| Scenario | Recommendation |
|----------|----------------|
| < 1ms work | Normal NIF |
| Can split into chunks | Yielding NIF |
| CPU-bound, can't split | Dirty CPU scheduler |
| Blocking I/O | Dirty I/O scheduler |
| Needs to track partial progress | Yielding NIF with resource |

## Dirty Scheduler Limitations

Operations that work on dirty schedulers:
- All term creation/extraction functions
- Resource allocation and access
- Memory allocation (`allocator::*`)
- Message sending (`env::send`)
- Process monitoring

Things to be careful about:
- Process may terminate mid-execution
- GC is delayed until NIF returns
- Can't call ETS functions that would block

## Best Practices

1. **Prefer yielding NIFs** when work can be split - they're more cooperative

2. **Check process liveness** in long-running dirty NIFs

3. **Use CPU-bound for compute** (crypto, compression, math)

4. **Use I/O-bound for blocking** (file I/O, network, external processes)

5. **Don't mix scheduler types** in the same logical operation

6. **Profile before optimizing** - measure actual execution time

7. **Store continuation state in resources** - stack is invalid across yields

## Complete Example: Parallel Hash

```c3
module hash_nif;

import c3nif;
import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;
import c3nif::scheduler;
import c3nif::binary;

// Hash a large binary - uses dirty CPU scheduler
<* nif: arity = 1, dirty = cpu *>
fn ErlNifTerm hash_binary(
    ErlNifEnv* raw_env,
    CInt argc,
    ErlNifTerm* argv
) {
    Env e = env::wrap(raw_env);

    Binary? bin = binary::inspect(&e, term::wrap(argv[0]));
    if (catch err = bin) {
        return term::make_badarg(&e).raw();
    }

    // Check process liveness for large binaries
    if (bin.size > 10 * 1024 * 1024) {
        // > 10MB - check periodically
        ulong hash = 0;
        char[] data = bin.as_slice();

        for (usz i = 0; i < bin.size; i++) {
            hash = hash * 31 + (ulong)data[i];

            if (i % (1024 * 1024) == 0) {  // Every 1MB
                if (!scheduler::is_process_alive(&e)) {
                    return term::make_atom(&e, "aborted").raw();
                }
            }
        }

        return term::make_ulong(&e, hash).raw();
    }

    // Small binary - just hash it
    ulong hash = compute_hash(bin.as_slice());
    return term::make_ulong(&e, hash).raw();
}

fn ulong compute_hash(char[] data) {
    ulong hash = 0;
    for (usz i = 0; i < data.len; i++) {
        hash = hash * 31 + (ulong)data[i];
    }
    return hash;
}
```
