/**
 * C3 FFI bindings to Erlang NIF API (erl_nif.h)
 *
 * This module provides low-level bindings to the Erlang NIF C API.
 * Higher-level wrappers are provided in other modules.
 */
module c3nif::erl_nif;

// =============================================================================
// Core Types
// =============================================================================

// ERL_NIF_TERM is an unsigned integer type (same size as pointer)
alias ErlNifTerm = CULong;

// Opaque environment pointer
alias ErlNifEnv = void;

// =============================================================================
// Function Pointer Types
// =============================================================================

// NIF function pointer type
alias NifFuncPtr = fn ErlNifTerm(ErlNifEnv*, CInt, ErlNifTerm*);

// NIF lifecycle callback types
alias LoadFn = fn CInt(ErlNifEnv*, void**, ErlNifTerm);
alias ReloadFn = fn CInt(ErlNifEnv*, void**, ErlNifTerm);
alias UpgradeFn = fn CInt(ErlNifEnv*, void**, void**, ErlNifTerm);
alias UnloadFn = fn void(ErlNifEnv*, void*);

// Resource callback types
alias ResourceDtorFn = fn void(ErlNifEnv*, void*);
alias ResourceStopFn = fn void(ErlNifEnv*, void*, CInt, CInt);
alias ResourceDownFn = fn void(ErlNifEnv*, void*, ErlNifPid*, void*);
alias ResourceDynCallFn = fn void(ErlNifEnv*, void*, void*);

// =============================================================================
// Structs
// =============================================================================

// Binary data structure
struct ErlNifBinary {
    CULong size;
    char* data;
    void* ref_bin;       // internal
    void*[2] __spare__;  // for future ABI compatibility
}

// Process ID
struct ErlNifPid {
    ErlNifTerm pid;  // internal, may change
}

// Port ID
struct ErlNifPort {
    ErlNifTerm port_id;  // internal, may change
}

// NIF function descriptor
struct ErlNifFunc {
    char* name;
    CUInt arity;
    NifFuncPtr fptr;
    CUInt flags;
}

// NIF entry point structure - returned by nif_init()
struct ErlNifEntry {
    CInt major;
    CInt minor;
    char* name;
    CInt num_of_funcs;
    ErlNifFunc* funcs;
    LoadFn load;
    ReloadFn reload;
    UpgradeFn upgrade;
    UnloadFn unload;
    char* vm_variant;           // Added in 2.1
    CUInt options;              // Added in 2.7
    CULong sizeof_ErlNifResourceTypeInit;  // Added in 2.12
    char* min_erts;             // Added in 2.14
}

// Opaque resource type handle
alias ErlNifResourceType = void;

// Resource type initialization (for enif_init_resource_type)
struct ErlNifResourceTypeInit {
    ResourceDtorFn dtor;
    ResourceStopFn stop;
    ResourceDownFn down;
    CInt members;
    ResourceDynCallFn dyncall;
}

// =============================================================================
// Enums
// =============================================================================

// Character encoding for string functions
enum ErlNifCharEncoding : const CInt {
    LATIN1 = 1
}

// Resource type flags
enum ErlNifResourceFlags : const CInt {
    RT_CREATE = 1,
    RT_TAKEOVER = 2
}

// Term type (from enif_term_type)
enum ErlNifTermType : const CInt {
    ATOM = 1,
    BITSTRING = 2,
    FLOAT = 3,
    FUN = 4,
    INTEGER = 5,
    LIST = 6,
    MAP = 7,
    PID = 8,
    PORT = 9,
    REFERENCE = 10,
    TUPLE = 11
}

// Dirty scheduler flags
enum ErlNifDirtyTaskFlags : const CInt {
    CPU_BOUND = 1,
    IO_BOUND = 2
}

// NIF function flags (used in ErlNifFunc.flags)
const CUInt ERL_NIF_DIRTY_JOB_CPU_BOUND = 1;
const CUInt ERL_NIF_DIRTY_JOB_IO_BOUND = 2;

// =============================================================================
// Constants
// =============================================================================

const CInt ERL_NIF_MAJOR_VERSION = 2;
const CInt ERL_NIF_MINOR_VERSION = 16;
const char* ERL_NIF_VM_VARIANT = "beam.vanilla";
const char* ERL_NIF_MIN_ERTS_VERSION = "erts-12.0";

// =============================================================================
// Core NIF API Functions
// =============================================================================

// --- Memory allocation ---
extern fn void* enif_alloc(CULong size) @extern("enif_alloc");
extern fn void enif_free(void* ptr) @extern("enif_free");
extern fn void* enif_realloc(void* ptr, CULong size) @extern("enif_realloc");

// --- Private data ---
extern fn void* enif_priv_data(ErlNifEnv* env) @extern("enif_priv_data");

// --- Type checking ---
extern fn CInt enif_is_atom(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_atom");
extern fn CInt enif_is_binary(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_binary");
extern fn CInt enif_is_ref(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_ref");
extern fn CInt enif_is_fun(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_fun");
extern fn CInt enif_is_pid(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_pid");
extern fn CInt enif_is_port(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_port");
extern fn CInt enif_is_list(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_list");
extern fn CInt enif_is_tuple(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_tuple");
extern fn CInt enif_is_map(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_map");
extern fn CInt enif_is_empty_list(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_empty_list");
extern fn CInt enif_is_number(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_number");
extern fn CInt enif_is_exception(ErlNifEnv* env, ErlNifTerm term) @extern("enif_is_exception");
extern fn ErlNifTermType enif_term_type(ErlNifEnv* env, ErlNifTerm term) @extern("enif_term_type");

// --- Term comparison ---
extern fn CInt enif_is_identical(ErlNifTerm lhs, ErlNifTerm rhs) @extern("enif_is_identical");
extern fn CInt enif_compare(ErlNifTerm lhs, ErlNifTerm rhs) @extern("enif_compare");

// --- Integer get/make ---
extern fn CInt enif_get_int(ErlNifEnv* env, ErlNifTerm term, CInt* ip) @extern("enif_get_int");
extern fn CInt enif_get_uint(ErlNifEnv* env, ErlNifTerm term, CUInt* ip) @extern("enif_get_uint");
extern fn CInt enif_get_long(ErlNifEnv* env, ErlNifTerm term, CLong* ip) @extern("enif_get_long");
extern fn CInt enif_get_ulong(ErlNifEnv* env, ErlNifTerm term, CULong* ip) @extern("enif_get_ulong");
extern fn CInt enif_get_int64(ErlNifEnv* env, ErlNifTerm term, long* ip) @extern("enif_get_int64");
extern fn CInt enif_get_uint64(ErlNifEnv* env, ErlNifTerm term, ulong* ip) @extern("enif_get_uint64");

extern fn ErlNifTerm enif_make_int(ErlNifEnv* env, CInt i) @extern("enif_make_int");
extern fn ErlNifTerm enif_make_uint(ErlNifEnv* env, CUInt i) @extern("enif_make_uint");
extern fn ErlNifTerm enif_make_long(ErlNifEnv* env, CLong i) @extern("enif_make_long");
extern fn ErlNifTerm enif_make_ulong(ErlNifEnv* env, CULong i) @extern("enif_make_ulong");
extern fn ErlNifTerm enif_make_int64(ErlNifEnv* env, long i) @extern("enif_make_int64");
extern fn ErlNifTerm enif_make_uint64(ErlNifEnv* env, ulong i) @extern("enif_make_uint64");

// --- Double get/make ---
extern fn CInt enif_get_double(ErlNifEnv* env, ErlNifTerm term, double* dp) @extern("enif_get_double");
extern fn ErlNifTerm enif_make_double(ErlNifEnv* env, double d) @extern("enif_make_double");

// --- Atom get/make ---
extern fn ErlNifTerm enif_make_atom(ErlNifEnv* env, char* name) @extern("enif_make_atom");
extern fn ErlNifTerm enif_make_atom_len(ErlNifEnv* env, char* name, CULong len) @extern("enif_make_atom_len");
extern fn CInt enif_make_existing_atom(ErlNifEnv* env, char* name, ErlNifTerm* atom, ErlNifCharEncoding encoding) @extern("enif_make_existing_atom");
extern fn CInt enif_make_existing_atom_len(ErlNifEnv* env, char* name, CULong len, ErlNifTerm* atom, ErlNifCharEncoding encoding) @extern("enif_make_existing_atom_len");
extern fn CInt enif_get_atom(ErlNifEnv* env, ErlNifTerm atom, char* buf, CUInt len, ErlNifCharEncoding encoding) @extern("enif_get_atom");
extern fn CInt enif_get_atom_length(ErlNifEnv* env, ErlNifTerm atom, CUInt* len, ErlNifCharEncoding encoding) @extern("enif_get_atom_length");

// --- Binary operations ---
extern fn CInt enif_inspect_binary(ErlNifEnv* env, ErlNifTerm bin_term, ErlNifBinary* bin) @extern("enif_inspect_binary");
extern fn CInt enif_inspect_iolist_as_binary(ErlNifEnv* env, ErlNifTerm term, ErlNifBinary* bin) @extern("enif_inspect_iolist_as_binary");
extern fn CInt enif_alloc_binary(CULong size, ErlNifBinary* bin) @extern("enif_alloc_binary");
extern fn CInt enif_realloc_binary(ErlNifBinary* bin, CULong size) @extern("enif_realloc_binary");
extern fn void enif_release_binary(ErlNifBinary* bin) @extern("enif_release_binary");
extern fn ErlNifTerm enif_make_binary(ErlNifEnv* env, ErlNifBinary* bin) @extern("enif_make_binary");
extern fn ErlNifTerm enif_make_sub_binary(ErlNifEnv* env, ErlNifTerm bin_term, CULong pos, CULong size) @extern("enif_make_sub_binary");
extern fn char* enif_make_new_binary(ErlNifEnv* env, CULong size, ErlNifTerm* termp) @extern("enif_make_new_binary");

// --- String operations ---
extern fn ErlNifTerm enif_make_string(ErlNifEnv* env, char* string, ErlNifCharEncoding encoding) @extern("enif_make_string");
extern fn ErlNifTerm enif_make_string_len(ErlNifEnv* env, char* string, CULong len, ErlNifCharEncoding encoding) @extern("enif_make_string_len");
extern fn CInt enif_get_string(ErlNifEnv* env, ErlNifTerm list, char* buf, CUInt len, ErlNifCharEncoding encoding) @extern("enif_get_string");

// --- List operations ---
extern fn ErlNifTerm enif_make_list_cell(ErlNifEnv* env, ErlNifTerm car, ErlNifTerm cdr) @extern("enif_make_list_cell");
extern fn ErlNifTerm enif_make_list_from_array(ErlNifEnv* env, ErlNifTerm* arr, CUInt cnt) @extern("enif_make_list_from_array");
extern fn CInt enif_get_list_cell(ErlNifEnv* env, ErlNifTerm term, ErlNifTerm* head, ErlNifTerm* tail) @extern("enif_get_list_cell");
extern fn CInt enif_get_list_length(ErlNifEnv* env, ErlNifTerm term, CUInt* len) @extern("enif_get_list_length");
extern fn CInt enif_make_reverse_list(ErlNifEnv* env, ErlNifTerm term, ErlNifTerm* list) @extern("enif_make_reverse_list");

// --- Tuple operations ---
extern fn ErlNifTerm enif_make_tuple_from_array(ErlNifEnv* env, ErlNifTerm* arr, CUInt cnt) @extern("enif_make_tuple_from_array");
extern fn CInt enif_get_tuple(ErlNifEnv* env, ErlNifTerm tpl, CInt* arity, ErlNifTerm** array) @extern("enif_get_tuple");

// --- Map operations ---
extern fn ErlNifTerm enif_make_new_map(ErlNifEnv* env) @extern("enif_make_new_map");
extern fn CInt enif_make_map_put(ErlNifEnv* env, ErlNifTerm map_in, ErlNifTerm key, ErlNifTerm value, ErlNifTerm* map_out) @extern("enif_make_map_put");
extern fn CInt enif_get_map_value(ErlNifEnv* env, ErlNifTerm map, ErlNifTerm key, ErlNifTerm* value) @extern("enif_get_map_value");
extern fn CInt enif_make_map_update(ErlNifEnv* env, ErlNifTerm map_in, ErlNifTerm key, ErlNifTerm value, ErlNifTerm* map_out) @extern("enif_make_map_update");
extern fn CInt enif_make_map_remove(ErlNifEnv* env, ErlNifTerm map_in, ErlNifTerm key, ErlNifTerm* map_out) @extern("enif_make_map_remove");
extern fn CInt enif_get_map_size(ErlNifEnv* env, ErlNifTerm term, CULong* size) @extern("enif_get_map_size");

// --- Reference ---
extern fn ErlNifTerm enif_make_ref(ErlNifEnv* env) @extern("enif_make_ref");

// --- Error handling ---
extern fn ErlNifTerm enif_make_badarg(ErlNifEnv* env) @extern("enif_make_badarg");
extern fn ErlNifTerm enif_raise_exception(ErlNifEnv* env, ErlNifTerm reason) @extern("enif_raise_exception");
extern fn CInt enif_has_pending_exception(ErlNifEnv* env, ErlNifTerm* reason) @extern("enif_has_pending_exception");

// --- Resource operations ---
extern fn ErlNifResourceType* enif_open_resource_type(
    ErlNifEnv* env,
    char* module_str,
    char* name_str,
    ResourceDtorFn dtor,
    ErlNifResourceFlags flags,
    ErlNifResourceFlags* tried
) @extern("enif_open_resource_type");

extern fn ErlNifResourceType* enif_init_resource_type(
    ErlNifEnv* env,
    char* name_str,
    ErlNifResourceTypeInit* init,
    ErlNifResourceFlags flags,
    ErlNifResourceFlags* tried
) @extern("enif_init_resource_type");

extern fn void* enif_alloc_resource(ErlNifResourceType* type, CULong size) @extern("enif_alloc_resource");
extern fn void enif_release_resource(void* obj) @extern("enif_release_resource");
extern fn void enif_keep_resource(void* obj) @extern("enif_keep_resource");
extern fn ErlNifTerm enif_make_resource(ErlNifEnv* env, void* obj) @extern("enif_make_resource");
extern fn CInt enif_get_resource(ErlNifEnv* env, ErlNifTerm term, ErlNifResourceType* type, void** objp) @extern("enif_get_resource");
extern fn CULong enif_sizeof_resource(void* obj) @extern("enif_sizeof_resource");

// --- Environment operations ---
extern fn ErlNifEnv* enif_alloc_env() @extern("enif_alloc_env");
extern fn void enif_free_env(ErlNifEnv* env) @extern("enif_free_env");
extern fn void enif_clear_env(ErlNifEnv* env) @extern("enif_clear_env");
extern fn ErlNifTerm enif_make_copy(ErlNifEnv* dst_env, ErlNifTerm src_term) @extern("enif_make_copy");

// --- Process operations ---
extern fn ErlNifPid* enif_self(ErlNifEnv* caller_env, ErlNifPid* pid) @extern("enif_self");
extern fn CInt enif_get_local_pid(ErlNifEnv* env, ErlNifTerm term, ErlNifPid* pid) @extern("enif_get_local_pid");
extern fn CInt enif_send(ErlNifEnv* env, ErlNifPid* to_pid, ErlNifEnv* msg_env, ErlNifTerm msg) @extern("enif_send");

// --- Scheduler operations ---
extern fn CInt enif_consume_timeslice(ErlNifEnv* env, CInt percent) @extern("enif_consume_timeslice");
extern fn ErlNifTerm enif_schedule_nif(
    ErlNifEnv* env,
    char* fun_name,
    CInt flags,
    NifFuncPtr fp,
    CInt argc,
    ErlNifTerm* argv
) @extern("enif_schedule_nif");

// --- Term serialization ---
extern fn CInt enif_term_to_binary(ErlNifEnv* env, ErlNifTerm term, ErlNifBinary* bin) @extern("enif_term_to_binary");
extern fn CULong enif_binary_to_term(ErlNifEnv* env, char* data, CULong size, ErlNifTerm* term, CUInt opts) @extern("enif_binary_to_term");
