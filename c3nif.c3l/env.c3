/**
 * Environment wrapper for NIF operations
 *
 * The Env struct wraps the ErlNifEnv pointer and provides safe,
 * ergonomic access to NIF environment operations.
 */
module c3nif::env;

import c3nif::erl_nif;

/**
 * Faults that can occur in environment operations.
 */
faultdef NO_PROCESS;    // Called from non-process context
faultdef ALLOC_FAILED;  // Memory allocation failed

/**
 * Wrapper around ErlNifEnv* providing safe environment operations.
 *
 * An environment is tied to a calling process and should only be used
 * within the NIF call that received it. For process-independent
 * environments, see OwnedEnv.
 */
struct Env {
    erl_nif::ErlNifEnv* inner;
}

/**
 * Process-independent environment for building terms outside of NIF calls.
 *
 * OwnedEnv can be used to build terms that will be sent to other processes
 * or stored for later use. The environment must be explicitly freed.
 */
struct OwnedEnv {
    erl_nif::ErlNifEnv* inner;
}

// =============================================================================
// Env Functions
// =============================================================================

/**
 * Wrap a raw ErlNifEnv pointer in an Env struct.
 */
fn Env wrap(erl_nif::ErlNifEnv* raw_env) {
    return (Env){ .inner = raw_env };
}

/**
 * Get the raw ErlNifEnv pointer.
 */
fn erl_nif::ErlNifEnv* Env.raw(&self) {
    return self.inner;
}

/**
 * Get private data associated with this NIF module.
 */
fn void* Env.priv_data(&self) {
    return erl_nif::enif_priv_data(self.inner);
}

/**
 * Get the PID of the calling process.
 * Returns error if called from a non-process context.
 */
fn erl_nif::ErlNifPid? Env.self(&self) {
    erl_nif::ErlNifPid pid;
    if (erl_nif::enif_self(self.inner, &pid) == null) {
        return NO_PROCESS?;
    }
    return pid;
}

/**
 * Send a message to a process.
 *
 * @param to_pid The target process ID
 * @param msg_env Environment containing the message (can be null for process-bound env)
 * @param msg The message term
 * @return true if send was successful
 */
fn bool Env.send(&self, erl_nif::ErlNifPid* to_pid, erl_nif::ErlNifEnv* msg_env, erl_nif::ErlNifTerm msg) {
    return erl_nif::enif_send(self.inner, to_pid, msg_env, msg) != 0;
}

/**
 * Consume a percentage of the current timeslice.
 *
 * Should be called by long-running NIFs to allow the scheduler
 * to preempt if needed. Returns true if the NIF should yield.
 *
 * @param percent Percentage of timeslice consumed (1-100)
 * @return true if the NIF has used its entire timeslice
 */
fn bool Env.consume_timeslice(&self, int percent) {
    // Validate range per NIF API docs
    int clamped = percent;
    if (clamped < 1) clamped = 1;
    if (clamped > 100) clamped = 100;
    return erl_nif::enif_consume_timeslice(self.inner, clamped) != 0;
}

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
fn bool Env.is_process_alive(&self) {
    return erl_nif::enif_is_current_process_alive(self.inner) != 0;
}

// =============================================================================
// OwnedEnv Functions
// =============================================================================

/**
 * Create a new process-independent environment.
 */
fn OwnedEnv? new_owned_env() {
    erl_nif::ErlNifEnv* env = erl_nif::enif_alloc_env();
    if (env == null) {
        return ALLOC_FAILED?;
    }
    return (OwnedEnv){ .inner = env };
}

/**
 * Get the raw ErlNifEnv pointer.
 */
fn erl_nif::ErlNifEnv* OwnedEnv.raw(&self) {
    return self.inner;
}

/**
 * Get an Env view of this OwnedEnv for term operations.
 */
fn Env OwnedEnv.as_env(&self) {
    return (Env){ .inner = self.inner };
}

/**
 * Clear all terms from this environment, making it reusable.
 */
fn void OwnedEnv.clear(&self) {
    erl_nif::enif_clear_env(self.inner);
}

/**
 * Copy a term from another environment into this one.
 */
fn erl_nif::ErlNifTerm OwnedEnv.copy_term(&self, erl_nif::ErlNifTerm src_term) {
    return erl_nif::enif_make_copy(self.inner, src_term);
}

/**
 * Send a message using this environment and clear it afterwards.
 *
 * @param caller_env The calling NIF's environment (or null)
 * @param to_pid Target process
 * @param msg Message to send (must be created in this OwnedEnv)
 * @return true if send was successful
 */
fn bool OwnedEnv.send(&self, erl_nif::ErlNifEnv* caller_env, erl_nif::ErlNifPid* to_pid, erl_nif::ErlNifTerm msg) {
    return erl_nif::enif_send(caller_env, to_pid, self.inner, msg) != 0;
}

/**
 * Free this environment.
 *
 * After calling this, the OwnedEnv should not be used.
 */
fn void OwnedEnv.free(&self) {
    erl_nif::enif_free_env(self.inner);
}
