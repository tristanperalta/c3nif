/**
 * Scheduler Support for C3nif
 *
 * This module provides high-level wrappers for BEAM scheduler operations
 * including dirty scheduler support, yielding NIFs, and thread type detection.
 *
 * ## Dirty Schedulers
 *
 * Use dirty schedulers for NIFs that take longer than 1ms:
 * - CPU_BOUND: For compute-intensive operations (crypto, compression, math)
 * - IO_BOUND: For I/O operations (file, network, blocking syscalls)
 *
 * Example - static dirty NIF declaration:
 *
 *     ErlNifFunc[1] nif_funcs = {
 *         { .name = "heavy_compute", .arity = 1, .fptr = &heavy_compute,
 *           .flags = erl_nif::ERL_NIF_DIRTY_JOB_CPU_BOUND },
 *     };
 *
 * Example - dynamic scheduling:
 *
 *     fn ErlNifTerm dispatch_heavy_work(
 *         ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
 *     ) {
 *         Env e = env::wrap(env_raw);
 *         // Schedule to run on dirty CPU scheduler
 *         return scheduler::schedule_nif(&e, "heavy_compute",
 *             DirtyFlags.CPU_BOUND, &do_heavy_compute, argc, argv).raw();
 *     }
 *
 * ## Yielding NIFs
 *
 * For operations that can be split into chunks, use yielding NIFs instead of
 * dirty schedulers. Yielding NIFs are always preferred when feasible because
 * they don't block dirty scheduler pools.
 *
 * Pattern:
 * 1. Store continuation context in a resource (stack is invalid across yields)
 * 2. Call schedule_nif with the continuation function
 * 3. Return the result of schedule_nif directly from your NIF
 *
 * ## Process Liveness
 *
 * On dirty schedulers, the calling process can terminate while the NIF runs.
 * Use is_process_alive() to check and abort early:
 *
 *     if (!e.is_process_alive()) {
 *         // Process terminated, clean up and return
 *         return term::make_atom(&e, "process_terminated");
 *     }
 */
module c3nif::scheduler;

import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;

// =============================================================================
// Thread Type Detection
// =============================================================================

/**
 * Type of scheduler thread the NIF is currently running on.
 */
enum ThreadType {
    UNDEFINED,   // Not running on a scheduler (shouldn't happen in NIFs)
    NORMAL,      // Normal scheduler thread
    DIRTY_CPU,   // Dirty CPU-bound scheduler
    DIRTY_IO     // Dirty I/O-bound scheduler
}

/**
 * Get the type of scheduler thread currently executing.
 */
fn ThreadType current_thread_type() {
    CInt t = erl_nif::enif_thread_type();
    switch (t) {
        case erl_nif::ERL_NIF_THR_NORMAL_SCHEDULER: return NORMAL;
        case erl_nif::ERL_NIF_THR_DIRTY_CPU_SCHEDULER: return DIRTY_CPU;
        case erl_nif::ERL_NIF_THR_DIRTY_IO_SCHEDULER: return DIRTY_IO;
        default: return UNDEFINED;
    }
}

/**
 * Check if currently running on a dirty scheduler.
 */
fn bool is_dirty_scheduler() {
    ThreadType t = current_thread_type();
    return t == DIRTY_CPU || t == DIRTY_IO;
}

/**
 * Check if currently running on a normal scheduler.
 */
fn bool is_normal_scheduler() {
    return current_thread_type() == NORMAL;
}

// =============================================================================
// Dirty Scheduler Flags
// =============================================================================

/**
 * Flags for scheduling NIFs on different scheduler types.
 * Use these constants with schedule_nif().
 */
const CInt SCHED_NORMAL = 0;      // Normal scheduler (default)
const CInt SCHED_CPU_BOUND = 1;   // Dirty CPU-bound scheduler
const CInt SCHED_IO_BOUND = 2;    // Dirty I/O-bound scheduler

// =============================================================================
// Schedule NIF Wrapper
// =============================================================================

/**
 * Schedule a NIF to run on the specified scheduler type.
 *
 * IMPORTANT: The calling NIF MUST return the result of this function directly.
 * Do not perform any other operations after calling schedule_nif.
 *
 * The scheduled NIF will receive the provided arguments. To pass state between
 * yields, store context in a resource and pass it as one of the arguments.
 *
 * @param e Current environment
 * @param fun_name Name for tracing/debugging (must be valid atom string)
 * @param flags Scheduler type (SCHED_NORMAL, SCHED_CPU_BOUND, SCHED_IO_BOUND)
 * @param fp Function pointer to the NIF to schedule
 * @param argc Argument count
 * @param argv Arguments to pass to the scheduled NIF
 * @return Term to return from the calling NIF
 */
fn Term schedule_nif(
    Env* e,
    char* fun_name,
    CInt flags,
    erl_nif::NifFuncPtr fp,
    CInt argc,
    ErlNifTerm* argv
) {
    ErlNifTerm result = erl_nif::enif_schedule_nif(
        e.raw(),
        fun_name,
        flags,
        fp,
        argc,
        argv
    );
    return term::wrap(result);
}

/**
 * Schedule a NIF on a dirty CPU-bound scheduler.
 * Convenience wrapper for schedule_nif with SCHED_CPU_BOUND flag.
 */
fn Term schedule_dirty_cpu(
    Env* e,
    char* fun_name,
    erl_nif::NifFuncPtr fp,
    CInt argc,
    ErlNifTerm* argv
) {
    return schedule_nif(e, fun_name, SCHED_CPU_BOUND, fp, argc, argv);
}

/**
 * Schedule a NIF on a dirty I/O-bound scheduler.
 * Convenience wrapper for schedule_nif with SCHED_IO_BOUND flag.
 */
fn Term schedule_dirty_io(
    Env* e,
    char* fun_name,
    erl_nif::NifFuncPtr fp,
    CInt argc,
    ErlNifTerm* argv
) {
    return schedule_nif(e, fun_name, SCHED_IO_BOUND, fp, argc, argv);
}

/**
 * Schedule a NIF on a normal scheduler.
 * Useful for switching back from a dirty scheduler to a normal one.
 */
fn Term schedule_normal(
    Env* e,
    char* fun_name,
    erl_nif::NifFuncPtr fp,
    CInt argc,
    ErlNifTerm* argv
) {
    return schedule_nif(e, fun_name, SCHED_NORMAL, fp, argc, argv);
}

// =============================================================================
// Process Liveness Check
// =============================================================================

/**
 * Check if the current process is still alive.
 *
 * IMPORTANT: This is primarily useful on dirty schedulers where a process
 * can be terminated while the NIF is still running. On normal schedulers,
 * this always returns true.
 *
 * When a process terminates during a dirty NIF:
 * - Links and monitors are triggered
 * - The registered name is released
 * - ETS tables are cleaned up
 * - BUT the NIF continues to execute
 *
 * Long-running dirty NIFs should periodically check this and abort early
 * if the process has terminated to avoid wasted work.
 */
fn bool is_process_alive(Env* e) {
    return erl_nif::enif_is_current_process_alive(e.raw()) != 0;
}
