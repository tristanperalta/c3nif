/**
 * BEAM Allocator Integration
 *
 * This module wraps BEAM's enif_alloc/enif_free/enif_realloc as a C3
 * Allocator interface, enabling BEAM-tracked memory allocation with
 * C3 standard library collections.
 *
 * ## Thread Safety
 *
 * All operations are fully thread-safe. Can be called from any thread:
 * - Scheduler threads
 * - Dirty scheduler threads
 * - User-created threads
 *
 * ## VM Integration
 *
 * All allocations are tracked by the BEAM VM under `ERTS_ALC_T_NIF` and
 * are visible in `erlang:memory()` reports.
 *
 * ## Strict Pairing
 *
 * Memory allocated with these functions MUST be freed with the matching
 * free function. NEVER mix with:
 * - System malloc/free
 * - Binary allocators (enif_alloc_binary/enif_release_binary)
 * - Resource allocators (enif_alloc_resource/enif_release_resource)
 *
 * ## Example
 *
 *     // Simple allocation
 *     void* ptr = allocator::alloc(1024);
 *     if (!ptr) {
 *         return term::make_error_atom(&e, "alloc_failed").raw();
 *     }
 *     defer allocator::free(ptr);
 *
 *     // With Allocator interface
 *     BeamAllocator beam;
 *     List{int} numbers;
 *     numbers.init(&beam);
 *     defer numbers.free();
 */
module c3nif::allocator;

import c3nif::erl_nif;
import std::core::mem;

// =============================================================================
// BeamAllocator - C3 Allocator Interface
// =============================================================================

/**
 * BeamAllocator wraps BEAM's enif_alloc/free/realloc as C3 Allocator.
 *
 * This enables using BEAM-managed memory with C3 standard library
 * collections like List, DString, HashMap, etc.
 *
 * The struct is stateless - BEAM's allocator is global.
 */
struct BeamAllocator (Allocator)
{
    // Placeholder field - struct cannot be zero-sized in C3
    // The allocator is stateless (BEAM's allocator is global)
    char _placeholder;
}

/**
 * Acquire memory from BEAM allocator.
 *
 * @param size Bytes to allocate (must be > 0)
 * @param init_type NO_ZERO or ZERO for initialization
 * @param alignment Required alignment (0 = default, must be power of 2)
 * @return Pointer to allocated memory, or OUT_OF_MEMORY fault
 *
 * Note: BEAM guarantees 8-byte alignment. For larger alignments (e.g., SIMD),
 * this function over-allocates and stores the original pointer in a header.
 */
fn void*? BeamAllocator.acquire(&self, usz size, AllocInitType init_type, usz alignment) @dynamic
{
    void* ptr;

    // Handle over-aligned allocations (BEAM guarantees 8 bytes)
    if (alignment > BEAM_ALIGNMENT)
    {
        ptr = alloc_aligned(size, alignment);
    }
    else
    {
        ptr = erl_nif::enif_alloc((CULong)size);
    }

    if (!ptr)
    {
        return mem::OUT_OF_MEMORY?;
    }

    // Zero-initialize if requested
    if (init_type == ZERO)
    {
        mem::clear(ptr, size, BEAM_ALIGNMENT);
    }

    return ptr;
}

/**
 * Resize previously allocated memory.
 *
 * @param ptr Previously allocated pointer (must not be null)
 * @param new_size New size in bytes (must be > 0)
 * @param alignment Required alignment for new allocation
 * @return New pointer (may differ from input), or OUT_OF_MEMORY fault
 */
fn void*? BeamAllocator.resize(&self, void* ptr, usz new_size, usz alignment) @dynamic
{
    void* new_ptr;

    // Handle over-aligned reallocation
    if (alignment > BEAM_ALIGNMENT)
    {
        new_ptr = realloc_aligned(ptr, new_size, alignment);
    }
    else
    {
        new_ptr = erl_nif::enif_realloc(ptr, (CULong)new_size);
    }

    if (!new_ptr)
    {
        return mem::OUT_OF_MEMORY?;
    }

    return new_ptr;
}

/**
 * Release memory back to BEAM allocator.
 *
 * @param ptr Pointer to free (must not be null)
 * @param aligned True if allocated with alignment > BEAM_ALIGNMENT
 */
fn void BeamAllocator.release(&self, void* ptr, bool aligned) @dynamic
{
    if (aligned)
    {
        free_aligned(ptr);
    }
    else
    {
        erl_nif::enif_free(ptr);
    }
}

// =============================================================================
// Constants
// =============================================================================

// BEAM guarantees 8-byte alignment (16 on Windows 64-bit)
const usz BEAM_ALIGNMENT = 8;

// =============================================================================
// Aligned Allocation Helpers
// =============================================================================

// Header stored before aligned memory to track original pointer
struct AlignedHeader
{
    void* original;  // Original pointer from enif_alloc
    usz size;        // Allocated size
}

/**
 * Allocate memory with specific alignment.
 * Over-allocates and stores original pointer in header.
 */
fn void* alloc_aligned(usz size, usz alignment) @private
{
    // Calculate total size needed: header + padding + data
    usz header_size = AlignedHeader.sizeof;
    usz total = header_size + alignment + size;

    void* raw = erl_nif::enif_alloc((CULong)total);
    if (!raw) return null;

    // Calculate aligned address after header
    usz raw_addr = (usz)raw;
    usz aligned_addr = (raw_addr + header_size + alignment - 1) & ~(alignment - 1);

    // Store header just before aligned data
    AlignedHeader* header = (AlignedHeader*)(aligned_addr - header_size);
    header.original = raw;
    header.size = size;

    return (void*)aligned_addr;
}

/**
 * Reallocate aligned memory.
 */
fn void* realloc_aligned(void* ptr, usz new_size, usz alignment) @private
{
    if (!ptr) return alloc_aligned(new_size, alignment);

    // Get original allocation info from header
    AlignedHeader* header = (AlignedHeader*)((usz)ptr - AlignedHeader.sizeof);
    usz old_size = header.size;

    // Allocate new aligned block
    void* new_ptr = alloc_aligned(new_size, alignment);
    if (!new_ptr) return null;

    // Copy data
    usz copy_size = old_size < new_size ? old_size : new_size;
    mem::copy(new_ptr, ptr, copy_size, BEAM_ALIGNMENT, BEAM_ALIGNMENT);

    // Free old block
    free_aligned(ptr);

    return new_ptr;
}

/**
 * Free aligned memory.
 */
fn void free_aligned(void* ptr) @private
{
    if (!ptr) return;

    // Get original pointer from header
    AlignedHeader* header = (AlignedHeader*)((usz)ptr - AlignedHeader.sizeof);
    erl_nif::enif_free(header.original);
}

// =============================================================================
// Global Instance
// =============================================================================

/**
 * Global BEAM allocator instance.
 *
 * Use this with C3 standard library collections:
 *
 *     List{int} numbers;
 *     numbers.init(&BEAM_ALLOCATOR);
 */
const BeamAllocator BEAM_ALLOCATOR = {};

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Allocate memory from BEAM. Returns null on failure.
 *
 * Thread-safe: Yes
 * VM-tracked: Yes (visible in erlang:memory())
 */
fn void* alloc(usz size)
{
    return erl_nif::enif_alloc((CULong)size);
}

/**
 * Allocate memory from BEAM. Returns fault on failure.
 *
 * Thread-safe: Yes
 * VM-tracked: Yes
 */
fn void*? alloc_try(usz size)
{
    void* ptr = erl_nif::enif_alloc((CULong)size);
    if (!ptr)
    {
        return mem::OUT_OF_MEMORY?;
    }
    return ptr;
}

/**
 * Allocate zero-initialized memory from BEAM. Returns null on failure.
 *
 * Thread-safe: Yes
 * VM-tracked: Yes
 */
fn void* calloc(usz size)
{
    void* ptr = erl_nif::enif_alloc((CULong)size);
    if (ptr)
    {
        mem::clear(ptr, size, mem::DEFAULT_MEM_ALIGNMENT);
    }
    return ptr;
}

/**
 * Reallocate memory. Returns null on failure.
 * Original pointer remains valid if realloc fails.
 *
 * Thread-safe: Yes
 * VM-tracked: Yes
 */
fn void* realloc(void* ptr, usz new_size)
{
    return erl_nif::enif_realloc(ptr, (CULong)new_size);
}

/**
 * Free memory allocated by alloc/calloc/realloc.
 * Safe to call with null pointer.
 *
 * Thread-safe: Yes
 */
fn void free(void* ptr)
{
    if (ptr)
    {
        erl_nif::enif_free(ptr);
    }
}
