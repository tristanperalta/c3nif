/**
 * C3 Macros for C3nif
 *
 * This module provides convenience macros to reduce boilerplate
 * in NIF implementations.
 *
 * ## Overview
 *
 * C3 macros expand at compile time and provide zero-overhead abstractions
 * for common NIF patterns. Macros that take expression parameters (`#param`)
 * use the `@` prefix convention per C3 naming rules.
 *
 * ## Usage
 *
 * Import this module to use the macros:
 *
 *     import c3nif::macros;
 *
 * ## Available Macros
 *
 * - `@require_type` - Validate term type (uses expression param for check fn)
 * - `get_resource` - Extract typed resource from term
 * - `nif_entry` - NIF entry point with fault barrier
 * - `@require_arg` - Safe argument extraction
 * - `@require_arg_int`, `@require_arg_long`, `@require_arg_double` - Typed argument extraction
 */
module c3nif::macros;

import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;
import c3nif::resource;

// =============================================================================
// Type Validation Macros
// =============================================================================

/**
 * Require a term to pass a type check, returning BADARG on failure.
 *
 * The check function should be one of the Term.is_* methods.
 *
 * Example:
 *     Term t = term::wrap(argv[0]);
 *     @require_type(t, is_atom, &e)!;  // Returns BADARG if not an atom
 *     @require_type(t, is_list, &e)!;  // Returns BADARG if not a list
 */
macro void? @require_type(Term t, #check_fn, Env* e) {
    if (!t.#check_fn(e)) {
        return term::BADARG?;
    }
}

// =============================================================================
// Resource Extraction Macros
// =============================================================================

/**
 * Extract a typed resource from a term with automatic error handling.
 *
 * Returns a properly cast pointer to the resource data, or propagates
 * the error if extraction fails.
 *
 * Example:
 *     struct MyData { int value; }
 *
 *     fn Term? use_resource(Env* e, Term t) {
 *         MyData* data = (MyData*)get_resource("MyResource", e, t)!;
 *         return term::make_int(e, data.value);
 *     }
 */
macro void*? get_resource(char* type_name, Env* e, Term t) {
    return resource::get(type_name, e, t);
}

// =============================================================================
// NIF Entry Point Macro
// =============================================================================

/**
 * NIF entry point wrapper with automatic fault barrier.
 *
 * This macro wraps the two-layer NIF pattern, handling environment
 * wrapping and fault-to-error conversion automatically.
 *
 * The implementation function should have signature:
 *     fn Term? impl(Env* e, ErlNifTerm* argv, CInt argc)
 *
 * Example:
 *     fn Term? add_impl(Env* e, ErlNifTerm* argv, CInt argc) {
 *         int a = term::wrap(argv[0]).get_int(e)!;
 *         int b = term::wrap(argv[1]).get_int(e)!;
 *         return term::make_int(e, a + b);
 *     }
 *
 *     fn ErlNifTerm add_nif(
 *         ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
 *     ) {
 *         return nif_entry(env_raw, argc, argv, &add_impl);
 *     }
 *
 * With custom error reason:
 *     return nif_entry(env_raw, argc, argv, &my_impl, "my_error");
 */
macro ErlNifTerm nif_entry(
    ErlNifEnv* env_raw,
    CInt argc,
    ErlNifTerm* argv,
    impl_fn,
    char* error_reason = "error"
) {
    Env e = env::wrap(env_raw);
    if (try result = impl_fn(&e, argv, argc)) {
        return result.raw();
    } else {
        return term::make_error_atom(&e, error_reason).raw();
    }
}

// =============================================================================
// Argument Extraction Macros
// =============================================================================

/**
 * Extract and validate an argument at the given index.
 *
 * Returns BADARG if the index is out of bounds.
 *
 * Example:
 *     Term arg0 = @require_arg(&e, argv, argc, 0)!;
 *     Term arg1 = @require_arg(&e, argv, argc, 1)!;
 */
macro Term? @require_arg(
    Env* e,
    ErlNifTerm* argv,
    CInt argc,
    CInt index
) {
    if (index < 0 || index >= argc) {
        return term::BADARG?;
    }
    return term::wrap(argv[index]);
}

/**
 * Extract an integer argument at the given index.
 *
 * Combines bounds checking and type conversion.
 *
 * Example:
 *     int value = @require_arg_int(&e, argv, argc, 0)!;
 */
macro int? @require_arg_int(
    Env* e,
    ErlNifTerm* argv,
    CInt argc,
    CInt index
) {
    Term? t = @require_arg(e, argv, argc, index);
    if (catch err = t) {
        return err?;
    }
    return t.get_int(e);
}

/**
 * Extract a long integer argument at the given index.
 *
 * Example:
 *     long value = @require_arg_long(&e, argv, argc, 0)!;
 */
macro long? @require_arg_long(
    Env* e,
    ErlNifTerm* argv,
    CInt argc,
    CInt index
) {
    Term? t = @require_arg(e, argv, argc, index);
    if (catch err = t) {
        return err?;
    }
    return t.get_long(e);
}

/**
 * Extract a double argument at the given index.
 *
 * Example:
 *     double value = @require_arg_double(&e, argv, argc, 0)!;
 */
macro double? @require_arg_double(
    Env* e,
    ErlNifTerm* argv,
    CInt argc,
    CInt index
) {
    Term? t = @require_arg(e, argv, argc, index);
    if (catch err = t) {
        return err?;
    }
    return t.get_double(e);
}

/**
 * Extract an unsigned integer argument at the given index.
 *
 * Example:
 *     uint value = @require_arg_uint(&e, argv, argc, 0)!;
 */
macro uint? @require_arg_uint(
    Env* e,
    ErlNifTerm* argv,
    CInt argc,
    CInt index
) {
    Term? t = @require_arg(e, argv, argc, index);
    if (catch err = t) {
        return err?;
    }
    return t.get_uint(e);
}

/**
 * Extract an unsigned long argument at the given index.
 *
 * Example:
 *     ulong value = @require_arg_ulong(&e, argv, argc, 0)!;
 */
macro ulong? @require_arg_ulong(
    Env* e,
    ErlNifTerm* argv,
    CInt argc,
    CInt index
) {
    Term? t = @require_arg(e, argv, argc, index);
    if (catch err = t) {
        return err?;
    }
    return t.get_ulong(e);
}
