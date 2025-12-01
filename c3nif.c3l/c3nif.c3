/**
 * C3nif - Write Erlang/Elixir NIFs in C3
 *
 * This is the main public API module that re-exports commonly used types
 * and functions from the c3nif library.
 *
 * Example usage:
 *
 *     import c3nif;
 *
 *     fn c3nif::ErlNifTerm my_nif(
 *         c3nif::ErlNifEnv* raw_env,
 *         CInt argc,
 *         c3nif::ErlNifTerm* argv
 *     ) {
 *         c3nif::Env e = c3nif::env::wrap(raw_env);
 *         c3nif::Term arg0 = c3nif::term::wrap(argv[0]);
 *
 *         int? value = arg0.get_int(&e);
 *         if (catch err = value) {
 *             return c3nif::term::make_badarg(&e).raw();
 *         }
 *
 *         return c3nif::term::make_int(&e, value, 2).raw();
 *     }
 */
module c3nif;

import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;
import c3nif::resource;
import c3nif::binary;
import c3nif::allocator;
import c3nif::safety;
import c3nif::scheduler;
import c3nif::macros;

// =============================================================================
// Version Information
// =============================================================================

const char* C3NIF_VERSION = "0.1.0";

// =============================================================================
// Type Aliases for convenience
// =============================================================================

// Note: Types are now directly accessible via imports (unqualified names).
// The types ErlNifTerm, ErlNifEnv, Env, Term, etc. do not need aliases.

// Re-export resource functions for convenience
alias register_resource_type = resource::register_type;
alias alloc_resource = resource::alloc;
alias make_resource_term = resource::make_term;
alias get_resource = resource::get;
alias keep_resource = resource::keep;
alias release_resource = resource::release;

// Re-export process monitoring functions
alias monitor_process = resource::monitor_process;
alias demonitor_process = resource::demonitor_process;
alias compare_monitors = resource::compare_monitors;

// Re-export monitor type

// Re-export binary type and functions
alias alloc_binary = binary::alloc;
alias inspect_binary = binary::inspect;
alias inspect_iolist = binary::inspect_iolist;
alias make_new_binary = binary::make_new;
alias make_sub_binary = binary::make_sub;
alias binary_from_slice = binary::from_slice;

// Re-export allocator type and functions
alias BEAM_ALLOCATOR = allocator::BEAM_ALLOCATOR;
alias beam_alloc = allocator::alloc;
alias beam_alloc_try = allocator::alloc_try;
alias beam_calloc = allocator::calloc;
alias beam_realloc = allocator::realloc;
alias beam_free = allocator::free;

// Re-export safety types and functions
alias nif_ok = safety::ok;
alias nif_badarg = safety::badarg;
alias nif_error = safety::error;
alias get_arg = safety::get_arg;
alias require_int = safety::require_int;
alias require_uint = safety::require_uint;
alias require_long = safety::require_long;
alias require_ulong = safety::require_ulong;
alias require_double = safety::require_double;
alias require_atom = safety::require_atom;
alias require_binary = safety::require_binary;
alias require_list = safety::require_list;
alias require_tuple = safety::require_tuple;
alias require_map = safety::require_map;
alias require_pid = safety::require_pid;
alias require_argc = safety::require_argc;
alias require_int_range = safety::require_int_range;
alias require_non_negative = safety::require_non_negative;
alias require_positive = safety::require_positive;
alias make_badarg_error = safety::make_badarg_error;
alias make_overflow_error = safety::make_overflow_error;
alias make_alloc_error = safety::make_alloc_error;
alias make_resource_error = safety::make_resource_error;
alias make_unknown_error = safety::make_unknown_error;

// Re-export scheduler types and functions
alias current_thread_type = scheduler::current_thread_type;
alias is_dirty_scheduler = scheduler::is_dirty_scheduler;
alias is_normal_scheduler = scheduler::is_normal_scheduler;
alias schedule_nif = scheduler::schedule_nif;
alias schedule_dirty_cpu = scheduler::schedule_dirty_cpu;
alias schedule_dirty_io = scheduler::schedule_dirty_io;
alias schedule_normal = scheduler::schedule_normal;
alias is_process_alive = scheduler::is_process_alive;
// Scheduler flag constants
alias SCHED_NORMAL = scheduler::SCHED_NORMAL;
alias SCHED_CPU_BOUND = scheduler::SCHED_CPU_BOUND;
alias SCHED_IO_BOUND = scheduler::SCHED_IO_BOUND;

// Note: Macros must be imported directly from c3nif::macros
// The following macros are available:
// - @require_type - Validate term type
// - @get_resource - Extract typed resource from term
// - nif_entry - NIF entry point with fault barrier (no @ - uses regular params)
// - @require_arg, @require_arg_int, @require_arg_long, etc.

// =============================================================================
// NIF Entry Helpers
// =============================================================================

// Callback function pointer types
alias LoadFn = fn CInt(ErlNifEnv*, void**, ErlNifTerm);
alias UnloadFn = fn void(ErlNifEnv*, void*);

/**
 * Create a properly initialized ErlNifEntry struct.
 *
 * This helper ensures all fields are set correctly for NIF registration.
 */
fn ErlNifEntry make_nif_entry(
    char* name,
    ErlNifFunc* funcs,
    int num_funcs,
    LoadFn load,
    UnloadFn unload
) {
    return (ErlNifEntry){
        .major = erl_nif::ERL_NIF_MAJOR_VERSION,
        .minor = erl_nif::ERL_NIF_MINOR_VERSION,
        .name = name,
        .num_of_funcs = num_funcs,
        .funcs = funcs,
        .load = load,
        .reload = null,
        .upgrade = null,
        .unload = unload,
        .vm_variant = erl_nif::ERL_NIF_VM_VARIANT,
        .options = 0,
        .sizeof_ErlNifResourceTypeInit = erl_nif::ErlNifResourceTypeInit.sizeof,
        .min_erts = erl_nif::ERL_NIF_MIN_ERTS_VERSION,
    };
}
