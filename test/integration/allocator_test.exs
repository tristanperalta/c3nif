# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.AllocatorNif do
  @nif_path_base "libC3nif.IntegrationTest.AllocatorNif"

  def load_nif(priv_dir) do
    nif_path =
      priv_dir
      |> Path.join(@nif_path_base)
      |> String.to_charlist()

    case :erlang.load_nif(nif_path, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Basic allocation tests
  def alloc_and_free(_size), do: :erlang.nif_error(:nif_not_loaded)
  def calloc_test(_size), do: :erlang.nif_error(:nif_not_loaded)
  def realloc_grow(_initial_size, _final_size), do: :erlang.nif_error(:nif_not_loaded)
  def realloc_shrink(_initial_size, _final_size), do: :erlang.nif_error(:nif_not_loaded)

  # Buffer pattern test
  def fill_buffer(_size, _value), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.AllocatorTest do
  use C3nif.Case, async: false

  @moduletag :integration

  @c3_code """
  module allocator_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::allocator;

  // =============================================================================
  // Basic Allocation NIFs
  // =============================================================================

  // NIF: alloc_and_free(size) -> :ok | {:error, reason}
  // Allocates memory, writes a pattern, verifies it, and frees
  fn ErlNifTerm alloc_and_free(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      int? size = arg.get_int(&e);
      if (catch err = size) {
          return term::make_badarg(&e).raw();
      }

      // Allocate memory
      void* ptr = allocator::alloc((usz)size);
      if (!ptr) {
          return term::make_error_atom(&e, "alloc_failed").raw();
      }

      // Write pattern
      char* data = (char*)ptr;
      for (int i = 0; i < size; i++) {
          data[i] = (char)(i % 256);
      }

      // Verify pattern
      for (int i = 0; i < size; i++) {
          if (data[i] != (char)(i % 256)) {
              allocator::free(ptr);
              return term::make_error_atom(&e, "verify_failed").raw();
          }
      }

      // Free memory
      allocator::free(ptr);

      return term::make_atom(&e, "ok").raw();
  }

  // NIF: calloc_test(size) -> :ok | {:error, reason}
  // Allocates zero-initialized memory and verifies it
  fn ErlNifTerm calloc_test(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      int? size = arg.get_int(&e);
      if (catch err = size) {
          return term::make_badarg(&e).raw();
      }

      // Allocate zero-initialized memory
      void* ptr = allocator::calloc((usz)size);
      if (!ptr) {
          return term::make_error_atom(&e, "alloc_failed").raw();
      }

      // Verify all zeros
      char* data = (char*)ptr;
      for (int i = 0; i < size; i++) {
          if (data[i] != 0) {
              allocator::free(ptr);
              return term::make_error_atom(&e, "not_zeroed").raw();
          }
      }

      allocator::free(ptr);
      return term::make_atom(&e, "ok").raw();
  }

  // NIF: realloc_grow(initial_size, final_size) -> :ok | {:error, reason}
  // Allocates, fills, grows, verifies original data preserved
  fn ErlNifTerm realloc_grow(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term init_arg = term::wrap(argv[0]);
      Term final_arg = term::wrap(argv[1]);

      int? initial = init_arg.get_int(&e);
      if (catch err = initial) {
          return term::make_badarg(&e).raw();
      }

      int? final_size = final_arg.get_int(&e);
      if (catch err = final_size) {
          return term::make_badarg(&e).raw();
      }

      // Allocate initial size
      void* ptr = allocator::alloc((usz)initial);
      if (!ptr) {
          return term::make_error_atom(&e, "alloc_failed").raw();
      }

      // Fill with pattern
      char* data = (char*)ptr;
      for (int i = 0; i < initial; i++) {
          data[i] = (char)(i % 256);
      }

      // Grow allocation
      void* new_ptr = allocator::realloc(ptr, (usz)final_size);
      if (!new_ptr) {
          allocator::free(ptr);
          return term::make_error_atom(&e, "realloc_failed").raw();
      }

      // Verify original data preserved
      data = (char*)new_ptr;
      for (int i = 0; i < initial; i++) {
          if (data[i] != (char)(i % 256)) {
              allocator::free(new_ptr);
              return term::make_error_atom(&e, "data_corrupted").raw();
          }
      }

      allocator::free(new_ptr);
      return term::make_atom(&e, "ok").raw();
  }

  // NIF: realloc_shrink(initial_size, final_size) -> :ok | {:error, reason}
  // Allocates, fills, shrinks, verifies remaining data preserved
  fn ErlNifTerm realloc_shrink(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term init_arg = term::wrap(argv[0]);
      Term final_arg = term::wrap(argv[1]);

      int? initial = init_arg.get_int(&e);
      if (catch err = initial) {
          return term::make_badarg(&e).raw();
      }

      int? final_size = final_arg.get_int(&e);
      if (catch err = final_size) {
          return term::make_badarg(&e).raw();
      }

      // Allocate initial size
      void* ptr = allocator::alloc((usz)initial);
      if (!ptr) {
          return term::make_error_atom(&e, "alloc_failed").raw();
      }

      // Fill with pattern
      char* data = (char*)ptr;
      for (int i = 0; i < initial; i++) {
          data[i] = (char)(i % 256);
      }

      // Shrink allocation
      void* new_ptr = allocator::realloc(ptr, (usz)final_size);
      if (!new_ptr) {
          allocator::free(ptr);
          return term::make_error_atom(&e, "realloc_failed").raw();
      }

      // Verify remaining data preserved
      data = (char*)new_ptr;
      for (int i = 0; i < final_size; i++) {
          if (data[i] != (char)(i % 256)) {
              allocator::free(new_ptr);
              return term::make_error_atom(&e, "data_corrupted").raw();
          }
      }

      allocator::free(new_ptr);
      return term::make_atom(&e, "ok").raw();
  }

  // NIF: fill_buffer(size, value) -> binary
  // Allocates, fills with value, returns as binary
  fn ErlNifTerm fill_buffer(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term size_arg = term::wrap(argv[0]);
      Term value_arg = term::wrap(argv[1]);

      int? size = size_arg.get_int(&e);
      if (catch err = size) {
          return term::make_badarg(&e).raw();
      }

      int? value = value_arg.get_int(&e);
      if (catch err = value) {
          return term::make_badarg(&e).raw();
      }

      // Allocate buffer
      void* ptr = allocator::alloc((usz)size);
      if (!ptr) {
          return term::make_error_atom(&e, "alloc_failed").raw();
      }

      // Fill with value
      char* data = (char*)ptr;
      for (int i = 0; i < size; i++) {
          data[i] = (char)value;
      }

      // Create binary from buffer
      char[] binary_data;
      Term result = c3nif::make_new_binary(&e, (usz)size, &binary_data);

      // Copy data to binary
      for (int i = 0; i < size; i++) {
          binary_data[i] = data[i];
      }

      // Free our buffer
      allocator::free(ptr);

      return result.raw();
  }

  // =============================================================================
  // NIF Entry
  // =============================================================================

  ErlNifFunc[5] nif_funcs = {
      { .name = "alloc_and_free", .arity = 1, .fptr = &alloc_and_free, .flags = 0 },
      { .name = "calloc_test", .arity = 1, .fptr = &calloc_test, .flags = 0 },
      { .name = "realloc_grow", .arity = 2, .fptr = &realloc_grow, .flags = 0 },
      { .name = "realloc_shrink", .arity = 2, .fptr = &realloc_shrink, .flags = 0 },
      { .name = "fill_buffer", .arity = 2, .fptr = &fill_buffer, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.AllocatorNif",
          &nif_funcs,
          5,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.AllocatorNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.AllocatorNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.AllocatorNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "basic allocation" do
    test "alloc_and_free works for small allocations" do
      assert C3nif.IntegrationTest.AllocatorNif.alloc_and_free(64) == :ok
    end

    test "alloc_and_free works for medium allocations" do
      assert C3nif.IntegrationTest.AllocatorNif.alloc_and_free(1024) == :ok
    end

    test "alloc_and_free works for large allocations" do
      assert C3nif.IntegrationTest.AllocatorNif.alloc_and_free(1_000_000) == :ok
    end
  end

  describe "zero initialization" do
    test "calloc returns zeroed memory for small size" do
      assert C3nif.IntegrationTest.AllocatorNif.calloc_test(64) == :ok
    end

    test "calloc returns zeroed memory for large size" do
      assert C3nif.IntegrationTest.AllocatorNif.calloc_test(10_000) == :ok
    end
  end

  describe "reallocation" do
    test "realloc grow preserves data" do
      assert C3nif.IntegrationTest.AllocatorNif.realloc_grow(100, 1000) == :ok
    end

    test "realloc shrink preserves remaining data" do
      assert C3nif.IntegrationTest.AllocatorNif.realloc_shrink(1000, 100) == :ok
    end

    test "realloc to same size works" do
      assert C3nif.IntegrationTest.AllocatorNif.realloc_grow(100, 100) == :ok
    end
  end

  describe "buffer pattern" do
    test "fill_buffer creates correct binary" do
      result = C3nif.IntegrationTest.AllocatorNif.fill_buffer(5, 42)
      assert result == <<42, 42, 42, 42, 42>>
    end

    test "fill_buffer works with zeros" do
      result = C3nif.IntegrationTest.AllocatorNif.fill_buffer(3, 0)
      assert result == <<0, 0, 0>>
    end

    test "fill_buffer works with max byte value" do
      result = C3nif.IntegrationTest.AllocatorNif.fill_buffer(4, 255)
      assert result == <<255, 255, 255, 255>>
    end
  end

  describe "stress test" do
    test "many small allocations" do
      for _ <- 1..100 do
        assert C3nif.IntegrationTest.AllocatorNif.alloc_and_free(64) == :ok
      end
    end

    test "alternating alloc and realloc" do
      for i <- 1..50 do
        size = i * 100
        assert C3nif.IntegrationTest.AllocatorNif.realloc_grow(size, size * 2) == :ok
      end
    end
  end
end
