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
alias ResourceDownFn = fn void(ErlNifEnv*, void*, ErlNifPid*, ErlNifMonitor*);
alias ResourceDynCallFn = fn void(ErlNifEnv*, void*, void*);

// Halt callback types (ERL_NIF 2.17, OTP 26)
// Signature: void on_halt(void* priv_data)
alias OnHaltFn = fn void(void*);
// Signature: void on_unload_thread(void* priv_data)
alias OnUnloadThreadFn = fn void(void*);

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

// Monitor handle (opaque, for process monitoring)
// Size: sizeof(void*) * 4 = 32 bytes on 64-bit systems
struct ErlNifMonitor {
    void*[4] data;  // Opaque monitor data (size matches ErlDrvMonitor in OTP)
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
constdef ErlNifCharEncoding : inline CInt {
    LATIN1 = 1,
    UTF8 = 2
}

// Resource type flags
constdef ErlNifResourceFlags : inline CInt {
    RT_CREATE = 1,
    RT_TAKEOVER = 2
}

// Term type (from enif_term_type)
constdef ErlNifTermType : inline CInt {
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
constdef ErlNifDirtyTaskFlags : inline CInt {
    CPU_BOUND = 1,
    IO_BOUND = 2
}

// NIF options for enif_set_option (ERL_NIF 2.17, OTP 26)
constdef ErlNifOption : inline CInt {
    DELAY_HALT = 1,
    ON_HALT = 2,
    ON_UNLOAD_THREAD = 3
}

// NIF function flags (used in ErlNifFunc.flags)
const CUInt ERL_NIF_DIRTY_JOB_CPU_BOUND = 1;
const CUInt ERL_NIF_DIRTY_JOB_IO_BOUND = 2;

// =============================================================================
// Constants
// =============================================================================

const CInt ERL_NIF_MAJOR_VERSION = 2;
const CInt ERL_NIF_MINOR_VERSION = 17;
const char* ERL_NIF_VM_VARIANT = "beam.vanilla";
const char* ERL_NIF_MIN_ERTS_VERSION = "erts-14.0";

// =============================================================================
// Core NIF API Functions
// =============================================================================

// --- Memory allocation ---
extern fn void* enif_alloc(CULong size) @cname("enif_alloc");
extern fn void enif_free(void* ptr) @cname("enif_free");
extern fn void* enif_realloc(void* ptr, CULong size) @cname("enif_realloc");

// --- Private data ---
extern fn void* enif_priv_data(ErlNifEnv* env) @cname("enif_priv_data");

// --- Type checking ---
extern fn CInt enif_is_atom(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_atom");
extern fn CInt enif_is_binary(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_binary");
extern fn CInt enif_is_ref(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_ref");
extern fn CInt enif_is_fun(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_fun");
extern fn CInt enif_is_pid(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_pid");
extern fn CInt enif_is_port(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_port");
extern fn CInt enif_is_list(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_list");
extern fn CInt enif_is_tuple(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_tuple");
extern fn CInt enif_is_map(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_map");
extern fn CInt enif_is_empty_list(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_empty_list");
extern fn CInt enif_is_number(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_number");
extern fn CInt enif_is_exception(ErlNifEnv* env, ErlNifTerm term) @cname("enif_is_exception");
extern fn ErlNifTermType enif_term_type(ErlNifEnv* env, ErlNifTerm term) @cname("enif_term_type");

// --- Term comparison ---
extern fn CInt enif_is_identical(ErlNifTerm lhs, ErlNifTerm rhs) @cname("enif_is_identical");
extern fn CInt enif_compare(ErlNifTerm lhs, ErlNifTerm rhs) @cname("enif_compare");

// --- Integer get/make ---
extern fn CInt enif_get_int(ErlNifEnv* env, ErlNifTerm term, CInt* ip) @cname("enif_get_int");
extern fn CInt enif_get_uint(ErlNifEnv* env, ErlNifTerm term, CUInt* ip) @cname("enif_get_uint");
extern fn CInt enif_get_long(ErlNifEnv* env, ErlNifTerm term, CLong* ip) @cname("enif_get_long");
extern fn CInt enif_get_ulong(ErlNifEnv* env, ErlNifTerm term, CULong* ip) @cname("enif_get_ulong");
extern fn CInt enif_get_int64(ErlNifEnv* env, ErlNifTerm term, long* ip) @cname("enif_get_int64");
extern fn CInt enif_get_uint64(ErlNifEnv* env, ErlNifTerm term, ulong* ip) @cname("enif_get_uint64");

extern fn ErlNifTerm enif_make_int(ErlNifEnv* env, CInt i) @cname("enif_make_int");
extern fn ErlNifTerm enif_make_uint(ErlNifEnv* env, CUInt i) @cname("enif_make_uint");
extern fn ErlNifTerm enif_make_long(ErlNifEnv* env, CLong i) @cname("enif_make_long");
extern fn ErlNifTerm enif_make_ulong(ErlNifEnv* env, CULong i) @cname("enif_make_ulong");
extern fn ErlNifTerm enif_make_int64(ErlNifEnv* env, long i) @cname("enif_make_int64");
extern fn ErlNifTerm enif_make_uint64(ErlNifEnv* env, ulong i) @cname("enif_make_uint64");

// --- Double get/make ---
extern fn CInt enif_get_double(ErlNifEnv* env, ErlNifTerm term, double* dp) @cname("enif_get_double");
extern fn ErlNifTerm enif_make_double(ErlNifEnv* env, double d) @cname("enif_make_double");

// --- Atom get/make ---
extern fn ErlNifTerm enif_make_atom(ErlNifEnv* env, char* name) @cname("enif_make_atom");
extern fn ErlNifTerm enif_make_atom_len(ErlNifEnv* env, char* name, CULong len) @cname("enif_make_atom_len");
extern fn CInt enif_make_existing_atom(ErlNifEnv* env, char* name, ErlNifTerm* atom, ErlNifCharEncoding encoding) @cname("enif_make_existing_atom");
extern fn CInt enif_make_existing_atom_len(ErlNifEnv* env, char* name, CULong len, ErlNifTerm* atom, ErlNifCharEncoding encoding) @cname("enif_make_existing_atom_len");
extern fn CInt enif_get_atom(ErlNifEnv* env, ErlNifTerm atom, char* buf, CUInt len, ErlNifCharEncoding encoding) @cname("enif_get_atom");
extern fn CInt enif_get_atom_length(ErlNifEnv* env, ErlNifTerm atom, CUInt* len, ErlNifCharEncoding encoding) @cname("enif_get_atom_length");
// Added in ERL_NIF 2.17 (OTP 26) — safe atom creation that returns 0 instead of aborting
// when the atom table is full. Unlike enif_make_atom, these take an encoding argument
// and support ERL_NIF_UTF8 for non-Latin-1 atom names.
extern fn CInt enif_make_new_atom(ErlNifEnv* env, char* name, ErlNifTerm* atom, ErlNifCharEncoding encoding) @cname("enif_make_new_atom");
extern fn CInt enif_make_new_atom_len(ErlNifEnv* env, char* name, CULong len, ErlNifTerm* atom, ErlNifCharEncoding encoding) @cname("enif_make_new_atom_len");

// --- Binary operations ---
extern fn CInt enif_inspect_binary(ErlNifEnv* env, ErlNifTerm bin_term, ErlNifBinary* bin) @cname("enif_inspect_binary");
extern fn CInt enif_inspect_iolist_as_binary(ErlNifEnv* env, ErlNifTerm term, ErlNifBinary* bin) @cname("enif_inspect_iolist_as_binary");
extern fn CInt enif_alloc_binary(CULong size, ErlNifBinary* bin) @cname("enif_alloc_binary");
extern fn CInt enif_realloc_binary(ErlNifBinary* bin, CULong size) @cname("enif_realloc_binary");
extern fn void enif_release_binary(ErlNifBinary* bin) @cname("enif_release_binary");
extern fn ErlNifTerm enif_make_binary(ErlNifEnv* env, ErlNifBinary* bin) @cname("enif_make_binary");
extern fn ErlNifTerm enif_make_sub_binary(ErlNifEnv* env, ErlNifTerm bin_term, CULong pos, CULong size) @cname("enif_make_sub_binary");
extern fn char* enif_make_new_binary(ErlNifEnv* env, CULong size, ErlNifTerm* termp) @cname("enif_make_new_binary");

// --- String operations ---
extern fn ErlNifTerm enif_make_string(ErlNifEnv* env, char* string, ErlNifCharEncoding encoding) @cname("enif_make_string");
extern fn ErlNifTerm enif_make_string_len(ErlNifEnv* env, char* string, CULong len, ErlNifCharEncoding encoding) @cname("enif_make_string_len");
extern fn CInt enif_get_string(ErlNifEnv* env, ErlNifTerm list, char* buf, CUInt len, ErlNifCharEncoding encoding) @cname("enif_get_string");
// Added in ERL_NIF 2.17 (OTP 26) — report string length without allocating.
extern fn CInt enif_get_string_length(ErlNifEnv* env, ErlNifTerm list, CUInt* len, ErlNifCharEncoding encoding) @cname("enif_get_string_length");

// --- List operations ---
extern fn ErlNifTerm enif_make_list_cell(ErlNifEnv* env, ErlNifTerm car, ErlNifTerm cdr) @cname("enif_make_list_cell");
extern fn ErlNifTerm enif_make_list_from_array(ErlNifEnv* env, ErlNifTerm* arr, CUInt cnt) @cname("enif_make_list_from_array");
extern fn CInt enif_get_list_cell(ErlNifEnv* env, ErlNifTerm term, ErlNifTerm* head, ErlNifTerm* tail) @cname("enif_get_list_cell");
extern fn CInt enif_get_list_length(ErlNifEnv* env, ErlNifTerm term, CUInt* len) @cname("enif_get_list_length");
extern fn CInt enif_make_reverse_list(ErlNifEnv* env, ErlNifTerm term, ErlNifTerm* list) @cname("enif_make_reverse_list");

// --- Tuple operations ---
extern fn ErlNifTerm enif_make_tuple_from_array(ErlNifEnv* env, ErlNifTerm* arr, CUInt cnt) @cname("enif_make_tuple_from_array");
extern fn CInt enif_get_tuple(ErlNifEnv* env, ErlNifTerm tpl, CInt* arity, ErlNifTerm** array) @cname("enif_get_tuple");

// --- Map operations ---
extern fn ErlNifTerm enif_make_new_map(ErlNifEnv* env) @cname("enif_make_new_map");
extern fn CInt enif_make_map_put(ErlNifEnv* env, ErlNifTerm map_in, ErlNifTerm key, ErlNifTerm value, ErlNifTerm* map_out) @cname("enif_make_map_put");
extern fn CInt enif_get_map_value(ErlNifEnv* env, ErlNifTerm map, ErlNifTerm key, ErlNifTerm* value) @cname("enif_get_map_value");
extern fn CInt enif_make_map_update(ErlNifEnv* env, ErlNifTerm map_in, ErlNifTerm key, ErlNifTerm value, ErlNifTerm* map_out) @cname("enif_make_map_update");
extern fn CInt enif_make_map_remove(ErlNifEnv* env, ErlNifTerm map_in, ErlNifTerm key, ErlNifTerm* map_out) @cname("enif_make_map_remove");
extern fn CInt enif_get_map_size(ErlNifEnv* env, ErlNifTerm term, CULong* size) @cname("enif_get_map_size");

// --- Reference ---
extern fn ErlNifTerm enif_make_ref(ErlNifEnv* env) @cname("enif_make_ref");

// --- Error handling ---
extern fn ErlNifTerm enif_make_badarg(ErlNifEnv* env) @cname("enif_make_badarg");
extern fn ErlNifTerm enif_raise_exception(ErlNifEnv* env, ErlNifTerm reason) @cname("enif_raise_exception");
extern fn CInt enif_has_pending_exception(ErlNifEnv* env, ErlNifTerm* reason) @cname("enif_has_pending_exception");

// --- Resource operations ---
extern fn ErlNifResourceType* enif_open_resource_type(
    ErlNifEnv* env,
    char* module_str,
    char* name_str,
    ResourceDtorFn dtor,
    ErlNifResourceFlags flags,
    ErlNifResourceFlags* tried
) @cname("enif_open_resource_type");

extern fn ErlNifResourceType* enif_init_resource_type(
    ErlNifEnv* env,
    char* name_str,
    ErlNifResourceTypeInit* init,
    ErlNifResourceFlags flags,
    ErlNifResourceFlags* tried
) @cname("enif_init_resource_type");

extern fn void* enif_alloc_resource(ErlNifResourceType* type, CULong size) @cname("enif_alloc_resource");
extern fn void enif_release_resource(void* obj) @cname("enif_release_resource");
extern fn void enif_keep_resource(void* obj) @cname("enif_keep_resource");
extern fn ErlNifTerm enif_make_resource(ErlNifEnv* env, void* obj) @cname("enif_make_resource");
extern fn CInt enif_get_resource(ErlNifEnv* env, ErlNifTerm term, ErlNifResourceType* type, void** objp) @cname("enif_get_resource");
extern fn CULong enif_sizeof_resource(void* obj) @cname("enif_sizeof_resource");

// --- Environment operations ---
extern fn ErlNifEnv* enif_alloc_env() @cname("enif_alloc_env");
extern fn void enif_free_env(ErlNifEnv* env) @cname("enif_free_env");
extern fn void enif_clear_env(ErlNifEnv* env) @cname("enif_clear_env");
extern fn ErlNifTerm enif_make_copy(ErlNifEnv* dst_env, ErlNifTerm src_term) @cname("enif_make_copy");

// --- Process operations ---
extern fn ErlNifPid* enif_self(ErlNifEnv* caller_env, ErlNifPid* pid) @cname("enif_self");
extern fn CInt enif_get_local_pid(ErlNifEnv* env, ErlNifTerm term, ErlNifPid* pid) @cname("enif_get_local_pid");
extern fn CInt enif_send(ErlNifEnv* env, ErlNifPid* to_pid, ErlNifEnv* msg_env, ErlNifTerm msg) @cname("enif_send");
// Note: enif_make_pid is a macro in OTP. Use make_pid() helper below instead.
// It simply returns the pid field from ErlNifPid.

// --- Process monitoring ---
extern fn CInt enif_monitor_process(ErlNifEnv* caller_env, void* obj, ErlNifPid* target_pid, ErlNifMonitor* monitor) @cname("enif_monitor_process");
extern fn CInt enif_demonitor_process(ErlNifEnv* caller_env, void* obj, ErlNifMonitor* monitor) @cname("enif_demonitor_process");
extern fn CInt enif_compare_monitors(ErlNifMonitor* mon1, ErlNifMonitor* mon2) @cname("enif_compare_monitors");

// --- Scheduler operations ---
extern fn CInt enif_consume_timeslice(ErlNifEnv* env, CInt percent) @cname("enif_consume_timeslice");
extern fn ErlNifTerm enif_schedule_nif(
    ErlNifEnv* env,
    char* fun_name,
    CInt flags,
    NifFuncPtr fp,
    CInt argc,
    ErlNifTerm* argv
) @cname("enif_schedule_nif");
extern fn CInt enif_thread_type() @cname("enif_thread_type");
extern fn CInt enif_is_current_process_alive(ErlNifEnv* env) @cname("enif_is_current_process_alive");

// --- NIF options (ERL_NIF 2.17, OTP 26) ---
// enif_set_option is variadic in C; bind one concrete form per option value.
// DELAY_HALT takes no trailing argument.
extern fn CInt enif_set_option_delay_halt(ErlNifEnv* env, ErlNifOption opt) @cname("enif_set_option");
// ON_HALT takes a halt callback.
extern fn CInt enif_set_option_on_halt(ErlNifEnv* env, ErlNifOption opt, OnHaltFn callback) @cname("enif_set_option");
// ON_UNLOAD_THREAD takes an unload-thread callback.
extern fn CInt enif_set_option_on_unload_thread(ErlNifEnv* env, ErlNifOption opt, OnUnloadThreadFn callback) @cname("enif_set_option");

// Thread type constants (returned by enif_thread_type)
const CInt ERL_NIF_THR_UNDEFINED = 0;
const CInt ERL_NIF_THR_NORMAL_SCHEDULER = 1;
const CInt ERL_NIF_THR_DIRTY_CPU_SCHEDULER = 2;
const CInt ERL_NIF_THR_DIRTY_IO_SCHEDULER = 3;

// --- Term serialization ---
extern fn CInt enif_term_to_binary(ErlNifEnv* env, ErlNifTerm term, ErlNifBinary* bin) @cname("enif_term_to_binary");
extern fn CULong enif_binary_to_term(ErlNifEnv* env, char* data, CULong size, ErlNifTerm* term, CUInt opts) @cname("enif_binary_to_term");

// =============================================================================
// Helper Functions (for C macros not callable from C3)
// =============================================================================

/**
 * Convert an ErlNifPid to an ErlNifTerm.
 * This is the C3 equivalent of the enif_make_pid macro.
 */
fn ErlNifTerm make_pid(ErlNifEnv* env, ErlNifPid* pid) {
    return pid.pid;
}
