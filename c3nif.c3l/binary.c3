/**
 * Binary handling for Erlang binaries
 *
 * This module provides type-safe wrappers for creating, inspecting,
 * and manipulating Erlang binaries with clear ownership semantics.
 *
 * ## Ownership Model
 *
 * Binaries can be:
 * - **Borrowed**: Inspected from Erlang term (read-only, NIF-lifetime)
 * - **Owned**: Allocated by us (mutable, must release or transfer)
 *
 * ## Thread Safety
 *
 * | Operation | Thread-Safe |
 * |-----------|-------------|
 * | alloc     | Yes         |
 * | release   | Yes         |
 * | realloc   | Yes (if owned) |
 * | inspect   | Needs env   |
 * | to_term   | Needs env   |
 *
 * ## Example
 *
 *     // Inspect a binary from Erlang
 *     Binary? bin = binary::inspect(&e, arg);
 *     if (catch err = bin) {
 *         return term::make_badarg(&e).raw();
 *     }
 *     char[] data = bin.as_slice();
 *
 *     // Allocate and return a binary
 *     Binary? owned = binary::alloc(100);
 *     if (catch err = owned) {
 *         return term::make_error_atom(&e, "alloc_failed").raw();
 *     }
 *     char[]? slice = owned.as_mut_slice();
 *     // ... fill in data ...
 *     term::Term result = owned.to_term(&e)!;
 *     return result.raw();
 */
module c3nif::binary;

import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;

// =============================================================================
// Fault Definitions
// =============================================================================

// Use term::BADARG for term type errors
faultdef ALLOC_FAILED;   // Binary allocation failed
faultdef NOT_OWNED;      // Operation requires owned binary

// =============================================================================
// Binary Struct
// =============================================================================

/**
 * Wrapper around ErlNifBinary with ownership semantics.
 *
 * Binaries can be:
 * - Borrowed: Inspected from Erlang term (read-only, NIF-lifetime)
 * - Owned: Allocated by us (mutable, must release or transfer)
 */
struct Binary {
    erl_nif::ErlNifBinary inner;
    bool owned;
}

// =============================================================================
// Binary Allocation (Owned)
// =============================================================================

/**
 * Allocate a new mutable binary.
 *
 * MUST either:
 * - Free with release()
 * - Transfer to Erlang with to_term()
 *
 * Thread-safe: Yes
 */
fn Binary? alloc(usz size) {
    erl_nif::ErlNifBinary bin;
    if (erl_nif::enif_alloc_binary((CULong)size, &bin) == 0) {
        return ALLOC_FAILED?;
    }
    return (Binary){ .inner = bin, .owned = true };
}

/**
 * Reallocate an owned binary to new size.
 * Data pointer may change - invalidates any slices.
 *
 * Thread-safe: Yes (if you own the binary)
 */
fn void? Binary.realloc(&self, usz new_size) {
    if (!self.owned) {
        return NOT_OWNED?;
    }
    if (erl_nif::enif_realloc_binary(&self.inner, (CULong)new_size) == 0) {
        return ALLOC_FAILED?;
    }
}

/**
 * Release an owned binary, freeing memory.
 * Do NOT call if you've transferred ownership with to_term().
 *
 * Thread-safe: Yes
 */
fn void Binary.release(&self) {
    if (self.owned) {
        erl_nif::enif_release_binary(&self.inner);
        self.owned = false;
    }
}

// =============================================================================
// Binary Inspection (Borrowed)
// =============================================================================

/**
 * Inspect a binary term for zero-copy read access.
 *
 * Returned binary is BORROWED - valid only during NIF call.
 * Do NOT call release() on borrowed binaries.
 *
 * Thread-safe: Requires environment
 */
fn Binary? inspect(env::Env* e, term::Term t) {
    erl_nif::ErlNifBinary bin;
    if (erl_nif::enif_inspect_binary(e.raw(), t.raw(), &bin) == 0) {
        return term::BADARG?;
    }
    return (Binary){ .inner = bin, .owned = false };
}

/**
 * Inspect an iolist, flattening to binary.
 * Data is copied to temp buffer, freed when NIF returns.
 *
 * Returned binary is BORROWED.
 *
 * Thread-safe: Requires environment
 */
fn Binary? inspect_iolist(env::Env* e, term::Term t) {
    erl_nif::ErlNifBinary bin;
    if (erl_nif::enif_inspect_iolist_as_binary(e.raw(), t.raw(), &bin) == 0) {
        return term::BADARG?;
    }
    return (Binary){ .inner = bin, .owned = false };
}

// =============================================================================
// Term Conversion
// =============================================================================

/**
 * Transfer owned binary to Erlang term.
 *
 * Ownership transfers - do NOT call release() after this.
 * The binary becomes immutable once transferred.
 *
 * Thread-safe: Requires environment
 */
fn term::Term? Binary.to_term(&self, env::Env* e) {
    if (!self.owned) {
        return NOT_OWNED?;
    }
    erl_nif::ErlNifTerm t = erl_nif::enif_make_binary(e.raw(), &self.inner);
    self.owned = false;  // Ownership transferred
    return term::wrap(t);
}

/**
 * Create binary and term in one step (most efficient for one-shot).
 * Returns term and fills data_out with writable slice.
 *
 * This is the most efficient way to create a binary when you don't
 * need to keep a mutable reference.
 *
 * Thread-safe: Requires environment
 */
fn term::Term make_new(env::Env* e, usz size, char[]* data_out) {
    erl_nif::ErlNifTerm t;
    char* ptr = erl_nif::enif_make_new_binary(e.raw(), (CULong)size, &t);
    *data_out = ptr[:size];
    return term::wrap(t);
}

/**
 * Create zero-copy sub-binary (slice view).
 * Creates a new term that references the same data.
 *
 * Thread-safe: Requires environment
 */
fn term::Term make_sub(env::Env* e, term::Term bin_term, usz pos, usz len) {
    erl_nif::ErlNifTerm t = erl_nif::enif_make_sub_binary(
        e.raw(), bin_term.raw(), (CULong)pos, (CULong)len
    );
    return term::wrap(t);
}

// =============================================================================
// Slice Access
// =============================================================================

/**
 * Get read-only slice view of binary data.
 * Valid only while Binary is valid.
 */
fn char[] Binary.as_slice(&self) {
    return self.inner.data[:self.inner.size];
}

/**
 * Get mutable slice view (owned binaries only).
 * Returns NOT_OWNED fault for borrowed binaries.
 */
fn char[]? Binary.as_mut_slice(&self) {
    if (!self.owned) {
        return NOT_OWNED?;
    }
    return self.inner.data[:self.inner.size];
}

/**
 * Get binary size in bytes.
 */
fn usz Binary.len(&self) {
    return (usz)self.inner.size;
}

/**
 * Get raw data pointer.
 * Prefer as_slice() for safer access.
 */
fn char* Binary.data(&self) {
    return self.inner.data;
}

/**
 * Check if this binary is owned (mutable).
 */
fn bool Binary.is_owned(&self) {
    return self.owned;
}

// =============================================================================
// Convenience Helpers
// =============================================================================

/**
 * Create a binary term by copying from a C3 slice.
 * Returns the term directly (ownership transferred to Erlang).
 */
fn term::Term from_slice(env::Env* e, char[] data) {
    char[] dest;
    term::Term t = make_new(e, data.len, &dest);
    for (usz i = 0; i < data.len; i++) {
        dest[i] = data[i];
    }
    return t;
}

/**
 * Copy a borrowed binary to an owned one.
 * Useful when you need to modify binary data.
 */
fn Binary? Binary.copy(&self) {
    Binary result = alloc(self.len())!;
    char[] src = self.as_slice();
    char[] dst = result.as_mut_slice()!!;
    for (usz i = 0; i < src.len; i++) {
        dst[i] = src[i];
    }
    return result;
}
