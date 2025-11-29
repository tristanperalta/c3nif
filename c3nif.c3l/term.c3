/**
 * Term encoding and decoding for Erlang terms
 *
 * This module provides type-safe wrappers for creating and extracting
 * values from Erlang terms.
 */
module c3nif::term;

import c3nif::erl_nif;
import c3nif::env;

/**
 * Faults for term decoding failures.
 */
faultdef BADARG;    // Term is not the expected type
faultdef OVERFLOW;  // Value doesn't fit in target type
faultdef ENCODING;  // String encoding error

/**
 * Wrapper around ErlNifTerm providing type-safe operations.
 */
struct Term {
    erl_nif::ErlNifTerm inner;
}

// =============================================================================
// Term Construction
// =============================================================================

/**
 * Wrap a raw ErlNifTerm.
 */
fn Term wrap(erl_nif::ErlNifTerm raw) {
    return (Term){ .inner = raw };
}

/**
 * Get the raw ErlNifTerm value.
 */
fn erl_nif::ErlNifTerm Term.raw(&self) {
    return self.inner;
}

// =============================================================================
// Type Checking
// =============================================================================

/**
 * Get the type of this term.
 */
fn erl_nif::ErlNifTermType Term.term_type(&self, env::Env* e) {
    return erl_nif::enif_term_type(e.inner, self.inner);
}

fn bool Term.is_atom(&self, env::Env* e) {
    return erl_nif::enif_is_atom(e.inner, self.inner) != 0;
}

fn bool Term.is_binary(&self, env::Env* e) {
    return erl_nif::enif_is_binary(e.inner, self.inner) != 0;
}

fn bool Term.is_ref(&self, env::Env* e) {
    return erl_nif::enif_is_ref(e.inner, self.inner) != 0;
}

fn bool Term.is_fun(&self, env::Env* e) {
    return erl_nif::enif_is_fun(e.inner, self.inner) != 0;
}

fn bool Term.is_pid(&self, env::Env* e) {
    return erl_nif::enif_is_pid(e.inner, self.inner) != 0;
}

fn bool Term.is_port(&self, env::Env* e) {
    return erl_nif::enif_is_port(e.inner, self.inner) != 0;
}

fn bool Term.is_list(&self, env::Env* e) {
    return erl_nif::enif_is_list(e.inner, self.inner) != 0;
}

fn bool Term.is_empty_list(&self, env::Env* e) {
    return erl_nif::enif_is_empty_list(e.inner, self.inner) != 0;
}

fn bool Term.is_tuple(&self, env::Env* e) {
    return erl_nif::enif_is_tuple(e.inner, self.inner) != 0;
}

fn bool Term.is_map(&self, env::Env* e) {
    return erl_nif::enif_is_map(e.inner, self.inner) != 0;
}

fn bool Term.is_number(&self, env::Env* e) {
    return erl_nif::enif_is_number(e.inner, self.inner) != 0;
}

fn bool Term.is_exception(&self, env::Env* e) {
    return erl_nif::enif_is_exception(e.inner, self.inner) != 0;
}

// =============================================================================
// Term Comparison
// =============================================================================

/**
 * Check if two terms are identical (same value and type).
 * Enables use of == and != operators.
 */
fn bool Term.equals(self, Term other) @operator(==) {
    return erl_nif::enif_is_identical(self.inner, other.inner) != 0;
}

/**
 * Compare two terms for ordering.
 * Returns negative if self < other, 0 if equal, positive if self > other.
 * Enables use with builtin comparison macros: less(), greater(), etc.
 */
fn int Term.compare_to(self, Term other) {
    return erl_nif::enif_compare(self.inner, other.inner);
}

// =============================================================================
// Integer Operations
// =============================================================================

/**
 * Create an integer term from a C int.
 */
fn Term make_int(env::Env* e, int value) {
    return (Term){ .inner = erl_nif::enif_make_int(e.inner, value) };
}

/**
 * Create an integer term from an unsigned int.
 */
fn Term make_uint(env::Env* e, uint value) {
    return (Term){ .inner = erl_nif::enif_make_uint(e.inner, value) };
}

/**
 * Create an integer term from a long.
 */
fn Term make_long(env::Env* e, long value) {
    return (Term){ .inner = erl_nif::enif_make_long(e.inner, (CLong)value) };
}

/**
 * Create an integer term from an unsigned long.
 */
fn Term make_ulong(env::Env* e, ulong value) {
    return (Term){ .inner = erl_nif::enif_make_ulong(e.inner, (CULong)value) };
}

/**
 * Extract a C int from a term.
 */
fn int? Term.get_int(&self, env::Env* e) {
    CInt result;
    if (erl_nif::enif_get_int(e.inner, self.inner, &result) == 0) {
        return BADARG?;
    }
    return (int)result;
}

/**
 * Extract an unsigned int from a term.
 */
fn uint? Term.get_uint(&self, env::Env* e) {
    CUInt result;
    if (erl_nif::enif_get_uint(e.inner, self.inner, &result) == 0) {
        return BADARG?;
    }
    return (uint)result;
}

/**
 * Extract a long from a term.
 */
fn long? Term.get_long(&self, env::Env* e) {
    CLong result;
    if (erl_nif::enif_get_long(e.inner, self.inner, &result) == 0) {
        return BADARG?;
    }
    return (long)result;
}

/**
 * Extract an unsigned long from a term.
 */
fn ulong? Term.get_ulong(&self, env::Env* e) {
    CULong result;
    if (erl_nif::enif_get_ulong(e.inner, self.inner, &result) == 0) {
        return BADARG?;
    }
    return (ulong)result;
}

// =============================================================================
// Float Operations
// =============================================================================

/**
 * Create a float term.
 */
fn Term make_double(env::Env* e, double value) {
    return (Term){ .inner = erl_nif::enif_make_double(e.inner, value) };
}

/**
 * Extract a double from a term.
 */
fn double? Term.get_double(&self, env::Env* e) {
    double result;
    if (erl_nif::enif_get_double(e.inner, self.inner, &result) == 0) {
        return BADARG?;
    }
    return result;
}

// =============================================================================
// Atom Operations
// =============================================================================

/**
 * Create an atom from a null-terminated string.
 * Note: This creates atoms unconditionally. Use make_existing_atom
 * to avoid atom table exhaustion attacks.
 */
fn Term make_atom(env::Env* e, char* name) {
    return (Term){ .inner = erl_nif::enif_make_atom(e.inner, name) };
}

/**
 * Create an atom from a string with explicit length.
 */
fn Term make_atom_len(env::Env* e, char* name, usz len) {
    return (Term){ .inner = erl_nif::enif_make_atom_len(e.inner, name, len) };
}

/**
 * Create an atom only if it already exists.
 * Returns BADARG if the atom doesn't exist.
 */
fn Term? make_existing_atom(env::Env* e, char* name) {
    erl_nif::ErlNifTerm atom;
    if (erl_nif::enif_make_existing_atom(e.inner, name, &atom, erl_nif::ErlNifCharEncoding.LATIN1) == 0) {
        return BADARG?;
    }
    return (Term){ .inner = atom };
}

/**
 * Get the length of an atom's name.
 */
fn uint? Term.get_atom_length(&self, env::Env* e) {
    CUInt len;
    if (erl_nif::enif_get_atom_length(e.inner, self.inner, &len, erl_nif::ErlNifCharEncoding.LATIN1) == 0) {
        return BADARG?;
    }
    return (uint)len;
}

// =============================================================================
// Binary Operations
// =============================================================================

/**
 * Inspect a binary term to get its data.
 * The returned binary data is valid only while the environment is valid.
 */
fn erl_nif::ErlNifBinary? Term.inspect_binary(&self, env::Env* e) {
    erl_nif::ErlNifBinary bin;
    if (erl_nif::enif_inspect_binary(e.inner, self.inner, &bin) == 0) {
        return BADARG?;
    }
    return bin;
}

/**
 * Create a new binary term with allocated space.
 * Returns the term and a pointer to the writable data.
 */
fn Term make_new_binary(env::Env* e, usz size, char** data_out) {
    erl_nif::ErlNifTerm term;
    *data_out = erl_nif::enif_make_new_binary(e.inner, size, &term);
    return (Term){ .inner = term };
}

/**
 * Create a sub-binary (a view into another binary).
 */
fn Term make_sub_binary(env::Env* e, Term bin_term, usz pos, usz size) {
    return (Term){ .inner = erl_nif::enif_make_sub_binary(e.inner, bin_term.inner, pos, size) };
}

// =============================================================================
// String Operations
// =============================================================================

/**
 * Create a string (list of characters) from a null-terminated C string.
 */
fn Term make_string(env::Env* e, char* string) {
    return (Term){ .inner = erl_nif::enif_make_string(e.inner, string, erl_nif::ErlNifCharEncoding.LATIN1) };
}

/**
 * Create a string from a C string with explicit length.
 */
fn Term make_string_len(env::Env* e, char* string, usz len) {
    return (Term){ .inner = erl_nif::enif_make_string_len(e.inner, string, len, erl_nif::ErlNifCharEncoding.LATIN1) };
}

// =============================================================================
// List Operations
// =============================================================================

/**
 * Create an empty list.
 */
fn Term make_empty_list(env::Env* e) {
    // Empty list is created by making a list with 0 elements
    return (Term){ .inner = erl_nif::enif_make_list_from_array(e.inner, null, 0) };
}

/**
 * Create a list cell (cons).
 */
fn Term make_list_cell(env::Env* e, Term head, Term tail) {
    return (Term){ .inner = erl_nif::enif_make_list_cell(e.inner, head.inner, tail.inner) };
}

/**
 * Create a list from an array of terms.
 */
fn Term make_list_from_array(env::Env* e, erl_nif::ErlNifTerm[] arr) {
    if (arr.len == 0) {
        return make_empty_list(e);
    }
    return (Term){ .inner = erl_nif::enif_make_list_from_array(e.inner, arr.ptr, (CUInt)arr.len) };
}

/**
 * Get the head and tail of a list.
 */
fn void? Term.get_list_cell(&self, env::Env* e, Term* head, Term* tail) {
    erl_nif::ErlNifTerm h, t;
    if (erl_nif::enif_get_list_cell(e.inner, self.inner, &h, &t) == 0) {
        return BADARG?;
    }
    *head = (Term){ .inner = h };
    *tail = (Term){ .inner = t };
}

/**
 * Get the length of a list.
 */
fn uint? Term.get_list_length(&self, env::Env* e) {
    CUInt len;
    if (erl_nif::enif_get_list_length(e.inner, self.inner, &len) == 0) {
        return BADARG?;
    }
    return (uint)len;
}

// =============================================================================
// Tuple Operations
// =============================================================================

/**
 * Create a tuple from an array of terms.
 */
fn Term make_tuple_from_array(env::Env* e, erl_nif::ErlNifTerm[] arr) {
    return (Term){ .inner = erl_nif::enif_make_tuple_from_array(e.inner, arr.ptr, (CUInt)arr.len) };
}

/**
 * Get the elements of a tuple.
 * Returns the arity and a pointer to the element array.
 */
fn int? Term.get_tuple(&self, env::Env* e, erl_nif::ErlNifTerm** array) {
    CInt arity;
    if (erl_nif::enif_get_tuple(e.inner, self.inner, &arity, array) == 0) {
        return BADARG?;
    }
    return (int)arity;
}

// =============================================================================
// Map Operations
// =============================================================================

/**
 * Create a new empty map.
 */
fn Term make_new_map(env::Env* e) {
    return (Term){ .inner = erl_nif::enif_make_new_map(e.inner) };
}

/**
 * Put a key-value pair into a map, returning a new map.
 */
fn Term? Term.map_put(&self, env::Env* e, Term key, Term value) {
    erl_nif::ErlNifTerm map_out;
    if (erl_nif::enif_make_map_put(e.inner, self.inner, key.inner, value.inner, &map_out) == 0) {
        return BADARG?;
    }
    return (Term){ .inner = map_out };
}

/**
 * Get a value from a map by key.
 */
fn Term? Term.map_get(&self, env::Env* e, Term key) {
    erl_nif::ErlNifTerm value;
    if (erl_nif::enif_get_map_value(e.inner, self.inner, key.inner, &value) == 0) {
        return BADARG?;
    }
    return (Term){ .inner = value };
}

/**
 * Get the size of a map.
 */
fn usz? Term.get_map_size(&self, env::Env* e) {
    CULong size;
    if (erl_nif::enif_get_map_size(e.inner, self.inner, &size) == 0) {
        return BADARG?;
    }
    return (usz)size;
}

// =============================================================================
// Reference Operations
// =============================================================================

/**
 * Create a new unique reference.
 */
fn Term make_ref(env::Env* e) {
    return (Term){ .inner = erl_nif::enif_make_ref(e.inner) };
}

// =============================================================================
// Error Handling
// =============================================================================

/**
 * Create a badarg exception term.
 */
fn Term make_badarg(env::Env* e) {
    return (Term){ .inner = erl_nif::enif_make_badarg(e.inner) };
}

/**
 * Raise an exception with the given reason.
 */
fn Term raise_exception(env::Env* e, Term reason) {
    return (Term){ .inner = erl_nif::enif_raise_exception(e.inner, reason.inner) };
}

// =============================================================================
// PID Operations
// =============================================================================

/**
 * Get a local PID from a term.
 */
fn erl_nif::ErlNifPid? Term.get_local_pid(&self, env::Env* e) {
    erl_nif::ErlNifPid pid;
    if (erl_nif::enif_get_local_pid(e.inner, self.inner, &pid) == 0) {
        return BADARG?;
    }
    return pid;
}

// =============================================================================
// Result Tuple Helpers
// =============================================================================

/**
 * Create an {:ok, value} tuple.
 */
fn Term make_ok_tuple(env::Env* e, Term value) {
    Term ok_atom = make_atom(e, "ok");
    erl_nif::ErlNifTerm[2] elements = { ok_atom.inner, value.inner };
    return make_tuple_from_array(e, elements[0:2]);
}

/**
 * Create an {:error, reason} tuple.
 */
fn Term make_error_tuple(env::Env* e, Term reason) {
    Term error_atom = make_atom(e, "error");
    erl_nif::ErlNifTerm[2] elements = { error_atom.inner, reason.inner };
    return make_tuple_from_array(e, elements[0:2]);
}

/**
 * Create an {:error, reason} tuple with an atom reason.
 */
fn Term make_error_atom(env::Env* e, char* reason) {
    return make_error_tuple(e, make_atom(e, reason));
}
