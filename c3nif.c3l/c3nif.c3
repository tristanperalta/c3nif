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
 *     fn c3nif::erl_nif::ErlNifTerm my_nif(
 *         c3nif::erl_nif::ErlNifEnv* raw_env,
 *         CInt argc,
 *         c3nif::erl_nif::ErlNifTerm* argv
 *     ) {
 *         c3nif::env::Env e = c3nif::env::wrap(raw_env);
 *         c3nif::term::Term arg0 = c3nif::term::wrap(argv[0]);
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

// =============================================================================
// Version Information
// =============================================================================

const char* C3NIF_VERSION = "0.1.0";

// =============================================================================
// Type Aliases for convenience
// =============================================================================

// Re-export common types
alias ErlNifTerm = erl_nif::ErlNifTerm;
alias ErlNifEnv = erl_nif::ErlNifEnv;
alias ErlNifEntry = erl_nif::ErlNifEntry;
alias ErlNifFunc = erl_nif::ErlNifFunc;
alias Env = env::Env;
alias Term = term::Term;

// =============================================================================
// NIF Entry Helpers
// =============================================================================

// Callback function pointer types
alias LoadFn = fn CInt(erl_nif::ErlNifEnv*, void**, erl_nif::ErlNifTerm);
alias UnloadFn = fn void(erl_nif::ErlNifEnv*, void*);

/**
 * Create a properly initialized ErlNifEntry struct.
 *
 * This helper ensures all fields are set correctly for NIF registration.
 */
fn erl_nif::ErlNifEntry make_nif_entry(
    char* name,
    erl_nif::ErlNifFunc* funcs,
    int num_funcs,
    LoadFn load,
    UnloadFn unload
) {
    return (erl_nif::ErlNifEntry){
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
