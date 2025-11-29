/**
 * Resource management for NIF resources
 *
 * This module provides type-safe wrappers for creating and managing
 * Erlang NIF resources. Resources are garbage-collected by the BEAM VM
 * and can have destructor callbacks for cleanup.
 *
 * Usage:
 *
 *     // In on_load callback:
 *     fn CInt on_load(ErlNifEnv* env, void** priv, ErlNifTerm load_info) {
 *         Env e = env::wrap(env);
 *         if (catch err = resource::register_type(&e, "MyResource", &my_dtor)) {
 *             return 1;
 *         }
 *         return 0;
 *     }
 *
 *     // In NIF function:
 *     void* ptr = resource::alloc("MyResource", MyStruct.sizeof)!;
 *     MyStruct* data = (MyStruct*)ptr;
 *     data.value = 42;
 *     Term t = resource::make_term(&e, ptr);
 *     resource::release(ptr);  // Term now owns the reference
 *     return t.raw();
 */
module c3nif::resource;

import c3nif::erl_nif;
import c3nif::env;
import c3nif::term;

// =============================================================================
// Fault Definitions
// =============================================================================

faultdef REGISTRATION_FAILED;  // Failed to register resource type
faultdef TYPE_NOT_FOUND;       // Resource type not found in registry
faultdef ALLOC_FAILED;         // Failed to allocate resource

// =============================================================================
// Resource Type Registry
// =============================================================================

const usz MAX_RESOURCE_TYPES = 32;

// Module-level registry for resource types
erl_nif::ErlNifResourceType*[MAX_RESOURCE_TYPES] g_resource_types;
char*[MAX_RESOURCE_TYPES] g_resource_names;
usz g_resource_count;

// =============================================================================
// Resource Type Registration
// =============================================================================

/**
 * Register a new resource type with an optional destructor callback.
 *
 * MUST be called from the on_load callback only. The destructor will be
 * called when the resource is garbage collected by the BEAM VM.
 *
 * Note: The destructor runs on an arbitrary scheduler thread and timing
 * is not deterministic.
 *
 * @param e Environment (must be from on_load callback)
 * @param type_name Unique name for this resource type
 * @param dtor Destructor callback, or null for no destructor
 * @return The registered resource type, or fault on failure
 */
fn erl_nif::ErlNifResourceType*? register_type(
    env::Env* e,
    char* type_name,
    erl_nif::ResourceDtorFn dtor
) {
    if (g_resource_count >= MAX_RESOURCE_TYPES) {
        return REGISTRATION_FAILED?;
    }

    erl_nif::ErlNifResourceTypeInit init = {
        .dtor = dtor,
        .stop = null,
        .down = null,
        .members = dtor != null ? 1 : 0,
        .dyncall = null
    };

    erl_nif::ErlNifResourceFlags tried;
    erl_nif::ErlNifResourceType* rt = erl_nif::enif_init_resource_type(
        e.raw(),
        type_name,
        &init,
        erl_nif::ErlNifResourceFlags.RT_CREATE,
        &tried
    );

    if (rt == null) {
        return REGISTRATION_FAILED?;
    }

    g_resource_names[g_resource_count] = type_name;
    g_resource_types[g_resource_count] = rt;
    g_resource_count++;

    return rt;
}

/**
 * Register a resource type with full callback support.
 *
 * Use this when you need stop, down, or dyncall callbacks in addition
 * to the destructor.
 */
fn erl_nif::ErlNifResourceType*? register_type_full(
    env::Env* e,
    char* type_name,
    erl_nif::ErlNifResourceTypeInit* init
) {
    if (g_resource_count >= MAX_RESOURCE_TYPES) {
        return REGISTRATION_FAILED?;
    }

    erl_nif::ErlNifResourceFlags tried;
    erl_nif::ErlNifResourceType* rt = erl_nif::enif_init_resource_type(
        e.raw(),
        type_name,
        init,
        erl_nif::ErlNifResourceFlags.RT_CREATE,
        &tried
    );

    if (rt == null) {
        return REGISTRATION_FAILED?;
    }

    g_resource_names[g_resource_count] = type_name;
    g_resource_types[g_resource_count] = rt;
    g_resource_count++;

    return rt;
}

// =============================================================================
// Resource Type Lookup
// =============================================================================

/**
 * Look up a registered resource type by name.
 */
fn erl_nif::ErlNifResourceType*? get_type(char* name) {
    for (usz i = 0; i < g_resource_count; i++) {
        if (streq(g_resource_names[i], name)) {
            return g_resource_types[i];
        }
    }
    return TYPE_NOT_FOUND?;
}

// Simple null-terminated string comparison
fn bool streq(char* a, char* b) {
    while (*a != 0 && *b != 0) {
        if (*a != *b) {
            return false;
        }
        a++;
        b++;
    }
    return *a == 0 && *b == 0;
}

// =============================================================================
// Resource Allocation
// =============================================================================

/**
 * Allocate a new resource of the given type.
 *
 * The returned pointer should be initialized with your data, then either:
 * - Converted to a term with make_term() and released with release()
 * - Kept with keep() if you need to store it in native code
 *
 * Initial reference count is 1.
 *
 * @param type_name Name of the registered resource type
 * @param size Size in bytes to allocate
 * @return Pointer to allocated resource, or fault on failure
 */
fn void*? alloc(char* type_name, usz size) {
    erl_nif::ErlNifResourceType* rt = get_type(type_name)!;
    void* ptr = erl_nif::enif_alloc_resource(rt, (CULong)size);
    if (ptr == null) {
        return ALLOC_FAILED?;
    }
    return ptr;
}

/**
 * Allocate a resource using a resource type pointer directly.
 * Useful when you've cached the resource type.
 */
fn void*? alloc_with_type(erl_nif::ErlNifResourceType* rt, usz size) {
    void* ptr = erl_nif::enif_alloc_resource(rt, (CULong)size);
    if (ptr == null) {
        return ALLOC_FAILED?;
    }
    return ptr;
}

// =============================================================================
// Resource Term Conversion
// =============================================================================

/**
 * Convert a resource pointer to an Erlang term.
 *
 * This increments the reference count. After calling this, you typically
 * want to call release() to decrement your reference, leaving the term
 * as the sole owner.
 *
 * @param e Environment
 * @param resource Pointer to the resource
 * @return Term representing the resource
 */
fn term::Term make_term(env::Env* e, void* resource) {
    erl_nif::ErlNifTerm t = erl_nif::enif_make_resource(e.raw(), resource);
    return term::wrap(t);
}

/**
 * Extract a resource pointer from an Erlang term.
 *
 * The returned pointer is valid as long as the term is reachable.
 * Does NOT increment the reference count.
 *
 * @param type_name Name of the expected resource type
 * @param e Environment
 * @param t Term containing the resource
 * @return Pointer to the resource, or fault if term is not this resource type
 */
fn void*? get(char* type_name, env::Env* e, term::Term t) {
    erl_nif::ErlNifResourceType* rt = get_type(type_name)!;
    void* ptr;
    if (erl_nif::enif_get_resource(e.raw(), t.raw(), rt, &ptr) == 0) {
        return term::BADARG?;
    }
    return ptr;
}

/**
 * Extract a resource using a resource type pointer directly.
 */
fn void*? get_with_type(erl_nif::ErlNifResourceType* rt, env::Env* e, term::Term t) {
    void* ptr;
    if (erl_nif::enif_get_resource(e.raw(), t.raw(), rt, &ptr) == 0) {
        return term::BADARG?;
    }
    return ptr;
}

// =============================================================================
// Reference Counting
// =============================================================================

/**
 * Increment the reference count of a resource.
 *
 * Use this when storing a resource pointer in native code that needs
 * to survive beyond the current NIF call.
 */
fn void keep(void* resource) {
    erl_nif::enif_keep_resource(resource);
}

/**
 * Decrement the reference count of a resource.
 *
 * When the reference count reaches zero, the destructor (if any) is called
 * and the memory is freed.
 *
 * Typical pattern after make_term():
 *     Term t = resource::make_term(&e, ptr);
 *     resource::release(ptr);  // Transfer ownership to term
 */
fn void release(void* resource) {
    erl_nif::enif_release_resource(resource);
}

// =============================================================================
// Resource Utilities
// =============================================================================

/**
 * Get the size of an allocated resource.
 */
fn usz sizeof_resource(void* resource) {
    return (usz)erl_nif::enif_sizeof_resource(resource);
}
