/**
 * Safety Hardening for C3nif
 *
 * This module provides error isolation patterns to prevent C3 faults from
 * crashing the BEAM VM. Since C3 has NO panic recovery (unlike Rust's
 * catch_unwind), the strategy focuses on PREVENTION through the fault system.
 *
 * ## Core Principle
 *
 * Assume any unhandled fault or panic crashes the BEAM. Design to prevent,
 * not recover.
 *
 * ## Two-Layer NIF Pattern
 *
 * Every NIF should use this pattern:
 *
 *     // INNER function - uses optionals, propagates faults with !
 *     fn Term? my_nif_impl(Env* e, ErlNifTerm* argv, CInt argc) {
 *         Term arg0 = safety::get_arg(argv, argc, 0)!;
 *         int value = safety::require_int(e, arg0)!;
 *         return term::make_int(e, value * 2);
 *     }
 *
 *     // OUTER function - fault barrier, catches ALL faults
 *     fn ErlNifTerm my_nif(
 *         ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
 *     ) {
 *         Env e = env::wrap(env_raw);
 *         Term? result = my_nif_impl(&e, argv, argc);
 *         if (catch fault = result) {
 *             return term::make_error_atom(&e, "error").raw();
 *         }
 *         return result.raw();
 *     }
 *
 * ## Key Rules
 *
 * 1. NEVER use !! (force unwrap) in NIF code
 * 2. Always handle optionals with if (catch ...)
 * 3. Use require_* helpers for argument extraction
 * 4. Every NIF entry point must have a fault barrier
 *
 * ## Limitations
 *
 * These scenarios WILL STILL CRASH THE BEAM:
 * - Segfaults from invalid pointer arithmetic
 * - Stack overflow
 * - Bugs in unsafe C3 code
 * - Integer overflow without trap-on-wrap
 *
 * Recommendation: Build with --safe during development, use ASan in CI.
 */
module c3nif::safety;

import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;

// =============================================================================
// NIF-Specific Faults
// =============================================================================

/**
 * Faults specific to NIF operations.
 * These extend the base faults in term.c3 (BADARG, OVERFLOW, ENCODING).
 */
faultdef ALLOC_FAILED;     // Memory allocation failure
faultdef RESOURCE_ERROR;   // Resource extraction failed
faultdef ENCODE_ERROR;     // Term encoding failed
faultdef ARGC_MISMATCH;    // Wrong number of arguments

// =============================================================================
// Result Type for NIF Operations
// =============================================================================

/**
 * NifResult wraps a Term with explicit error handling.
 * Forces callers to handle errors before accessing the value.
 *
 * Example:
 *     NifResult result = safety::ok(term::make_int(&e, 42));
 *     if (result.is_error) {
 *         return result.value.raw();  // Return error term
 *     }
 *     // Use result.value safely
 */
struct NifResult {
    Term value;
    bool is_error;
}

/**
 * Create a successful NifResult.
 */
fn NifResult ok(Term t) {
    return { .value = t, .is_error = false };
}

/**
 * Create a badarg error NifResult.
 */
fn NifResult badarg(Env* e) {
    return { .value = term::make_badarg(e), .is_error = true };
}

/**
 * Create an error NifResult with custom error atom.
 */
fn NifResult error(Env* e, char* reason) {
    return { .value = term::make_error_atom(e, reason), .is_error = true };
}

// =============================================================================
// Argument Validation Helpers
// =============================================================================

/**
 * Validate argument count matches expected.
 */
fn bool check_argc(CInt expected, CInt actual) {
    return expected == actual;
}

/**
 * Require exact argument count, returning fault if mismatch.
 */
fn void? require_argc(CInt expected, CInt actual) {
    if (expected != actual) {
        return ARGC_MISMATCH?;
    }
}

/**
 * Safe argument access with bounds checking.
 * Returns the argument as a Term, or BADARG if index out of bounds.
 */
fn Term? get_arg(ErlNifTerm* argv, CInt argc, CInt index) {
    if (index < 0 || index >= argc) {
        return term::BADARG?;
    }
    return term::wrap(argv[index]);
}

/**
 * Safe integer extraction - returns BADARG fault instead of crashing.
 */
fn int? require_int(Env* e, Term t) {
    return t.get_int(e);
}

/**
 * Safe unsigned integer extraction.
 */
fn uint? require_uint(Env* e, Term t) {
    return t.get_uint(e);
}

/**
 * Safe long extraction.
 */
fn long? require_long(Env* e, Term t) {
    return t.get_long(e);
}

/**
 * Safe unsigned long extraction.
 */
fn ulong? require_ulong(Env* e, Term t) {
    return t.get_ulong(e);
}

/**
 * Safe double extraction.
 */
fn double? require_double(Env* e, Term t) {
    return t.get_double(e);
}

/**
 * Require an atom argument.
 */
fn void? require_atom(Env* e, Term t) {
    if (!t.is_atom(e)) {
        return term::BADARG?;
    }
}

/**
 * Require a binary argument.
 */
fn ErlNifBinary? require_binary(Env* e, Term t) {
    return t.inspect_binary(e);
}

/**
 * Require a list argument.
 */
fn void? require_list(Env* e, Term t) {
    if (!t.is_list(e)) {
        return term::BADARG?;
    }
}

/**
 * Require a tuple argument.
 */
fn void? require_tuple(Env* e, Term t) {
    if (!t.is_tuple(e)) {
        return term::BADARG?;
    }
}

/**
 * Require a map argument.
 */
fn void? require_map(Env* e, Term t) {
    if (!t.is_map(e)) {
        return term::BADARG?;
    }
}

/**
 * Require a PID argument.
 */
fn ErlNifPid? require_pid(Env* e, Term t) {
    return t.get_local_pid(e);
}

// =============================================================================
// Range Validation
// =============================================================================

/**
 * Require an integer within a range (inclusive).
 */
fn int? require_int_range(Env* e, Term t, int min, int max) {
    int? val = t.get_int(e);
    if (catch err = val) {
        return err?;
    }
    if (val < min || val > max) {
        return term::BADARG?;
    }
    return val;
}

/**
 * Require a non-negative integer.
 */
fn int? require_non_negative(Env* e, Term t) {
    int? val = t.get_int(e);
    if (catch err = val) {
        return err?;
    }
    if (val < 0) {
        return term::BADARG?;
    }
    return val;
}

/**
 * Require a positive integer (> 0).
 */
fn int? require_positive(Env* e, Term t) {
    int? val = t.get_int(e);
    if (catch err = val) {
        return err?;
    }
    if (val <= 0) {
        return term::BADARG?;
    }
    return val;
}

// =============================================================================
// Fault Handling Helpers
// =============================================================================

/**
 * Make an error tuple for BADARG fault.
 */
fn Term make_badarg_error(Env* e) {
    return term::make_error_atom(e, "badarg");
}

/**
 * Make an error tuple for OVERFLOW fault.
 */
fn Term make_overflow_error(Env* e) {
    return term::make_error_atom(e, "overflow");
}

/**
 * Make an error tuple for ALLOC_FAILED fault.
 */
fn Term make_alloc_error(Env* e) {
    return term::make_error_atom(e, "alloc_failed");
}

/**
 * Make an error tuple for RESOURCE_ERROR fault.
 */
fn Term make_resource_error(Env* e) {
    return term::make_error_atom(e, "resource_error");
}

/**
 * Make a generic unknown error tuple.
 */
fn Term make_unknown_error(Env* e) {
    return term::make_error_atom(e, "unknown_error");
}
