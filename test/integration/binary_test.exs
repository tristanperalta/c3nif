# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.BinaryNif do
  @nif_path_base "libC3nif.IntegrationTest.BinaryNif"

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

  # Inspection tests
  def get_binary_size(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def get_first_byte(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def sum_bytes(_binary), do: :erlang.nif_error(:nif_not_loaded)

  # Allocation tests
  def make_zeros(_size), do: :erlang.nif_error(:nif_not_loaded)
  def make_sequence(_size), do: :erlang.nif_error(:nif_not_loaded)
  def copy_binary(_binary), do: :erlang.nif_error(:nif_not_loaded)

  # Sub-binary tests
  def get_slice(_binary, _pos, _len), do: :erlang.nif_error(:nif_not_loaded)

  # Iolist tests
  def flatten_iolist(_iolist), do: :erlang.nif_error(:nif_not_loaded)

  # Realloc test
  def make_and_grow(_initial_size, _final_size), do: :erlang.nif_error(:nif_not_loaded)

  # from_slice test
  def echo_binary(_binary), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.BinaryTest do
  use C3nif.Case, async: false

  @moduletag :integration

  @c3_code """
  module binary_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::binary;

  // =============================================================================
  // Inspection NIFs
  // =============================================================================

  // NIF: get_binary_size(binary) -> integer
  fn erl_nif::ErlNifTerm get_binary_size(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      binary::Binary? bin = binary::inspect(&e, arg);
      if (catch err = bin) {
          return term::make_badarg(&e).raw();
      }

      return term::make_int(&e, (int)bin.len()).raw();
  }

  // NIF: get_first_byte(binary) -> integer | :empty
  fn erl_nif::ErlNifTerm get_first_byte(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      binary::Binary? bin = binary::inspect(&e, arg);
      if (catch err = bin) {
          return term::make_badarg(&e).raw();
      }

      if (bin.len() == 0) {
          return term::make_atom(&e, "empty").raw();
      }

      char[] slice = bin.as_slice();
      return term::make_int(&e, (int)slice[0]).raw();
  }

  // NIF: sum_bytes(binary) -> integer
  fn erl_nif::ErlNifTerm sum_bytes(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      binary::Binary? bin = binary::inspect(&e, arg);
      if (catch err = bin) {
          return term::make_badarg(&e).raw();
      }

      char[] slice = bin.as_slice();
      long sum = 0;
      for (usz i = 0; i < slice.len; i++) {
          sum += (long)slice[i];
      }

      return term::make_int(&e, (int)sum).raw();
  }

  // =============================================================================
  // Allocation NIFs
  // =============================================================================

  // NIF: make_zeros(size) -> binary
  fn erl_nif::ErlNifTerm make_zeros(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      int? size = arg.get_int(&e);
      if (catch err = size) {
          return term::make_badarg(&e).raw();
      }

      binary::Binary? bin = binary::alloc((usz)size);
      if (catch err = bin) {
          return term::make_error_atom(&e, "alloc_failed").raw();
      }

      char[]? slice = bin.as_mut_slice();
      if (catch err = slice) {
          bin.release();
          return term::make_error_atom(&e, "not_owned").raw();
      }

      // Fill with zeros
      for (usz i = 0; i < slice.len; i++) {
          slice[i] = 0;
      }

      term::Term? result = bin.to_term(&e);
      if (catch err = result) {
          bin.release();
          return term::make_error_atom(&e, "transfer_failed").raw();
      }

      return result.raw();
  }

  // NIF: make_sequence(size) -> binary (bytes 0, 1, 2, ... mod 256)
  fn erl_nif::ErlNifTerm make_sequence(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      int? size = arg.get_int(&e);
      if (catch err = size) {
          return term::make_badarg(&e).raw();
      }

      // Use make_new for one-shot allocation
      char[] data;
      term::Term result = binary::make_new(&e, (usz)size, &data);

      for (usz i = 0; i < data.len; i++) {
          data[i] = (char)(i % 256);
      }

      return result.raw();
  }

  // NIF: copy_binary(binary) -> binary (tests Binary.copy)
  fn erl_nif::ErlNifTerm copy_binary(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      binary::Binary? orig = binary::inspect(&e, arg);
      if (catch err = orig) {
          return term::make_badarg(&e).raw();
      }

      // Copy borrowed to owned
      binary::Binary? owned = orig.copy();
      if (catch err = owned) {
          return term::make_error_atom(&e, "copy_failed").raw();
      }

      // Transfer to Erlang
      term::Term? result = owned.to_term(&e);
      if (catch err = result) {
          owned.release();
          return term::make_error_atom(&e, "transfer_failed").raw();
      }

      return result.raw();
  }

  // =============================================================================
  // Sub-binary NIFs
  // =============================================================================

  // NIF: get_slice(binary, pos, len) -> binary
  fn erl_nif::ErlNifTerm get_slice(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term bin_arg = term::wrap(argv[0]);
      term::Term pos_arg = term::wrap(argv[1]);
      term::Term len_arg = term::wrap(argv[2]);

      int? pos = pos_arg.get_int(&e);
      if (catch err = pos) {
          return term::make_badarg(&e).raw();
      }

      int? len = len_arg.get_int(&e);
      if (catch err = len) {
          return term::make_badarg(&e).raw();
      }

      // Create zero-copy sub-binary
      term::Term result = binary::make_sub(&e, bin_arg, (usz)pos, (usz)len);
      return result.raw();
  }

  // =============================================================================
  // Iolist NIFs
  // =============================================================================

  // NIF: flatten_iolist(iolist) -> binary
  fn erl_nif::ErlNifTerm flatten_iolist(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      binary::Binary? bin = binary::inspect_iolist(&e, arg);
      if (catch err = bin) {
          return term::make_badarg(&e).raw();
      }

      // The iolist was flattened to a temp buffer, return the size and first byte
      // as a tuple to verify it worked
      usz size = bin.len();
      char first = 0;
      if (size > 0) {
          first = bin.as_slice()[0];
      }

      // Build {:ok, size, first_byte} tuple
      term::Term ok = term::make_atom(&e, "ok");
      term::Term size_term = term::make_int(&e, (int)size);
      term::Term first_term = term::make_int(&e, (int)first);
      erl_nif::ErlNifTerm[3] elements = { ok.raw(), size_term.raw(), first_term.raw() };
      return term::make_tuple_from_array(&e, elements[0:3]).raw();
  }

  // =============================================================================
  // Realloc NIFs
  // =============================================================================

  // NIF: make_and_grow(initial_size, final_size) -> binary
  fn erl_nif::ErlNifTerm make_and_grow(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term init_arg = term::wrap(argv[0]);
      term::Term final_arg = term::wrap(argv[1]);

      int? initial = init_arg.get_int(&e);
      if (catch err = initial) {
          return term::make_badarg(&e).raw();
      }

      int? final_size = final_arg.get_int(&e);
      if (catch err = final_size) {
          return term::make_badarg(&e).raw();
      }

      // Allocate initial size
      binary::Binary? bin = binary::alloc((usz)initial);
      if (catch err = bin) {
          return term::make_error_atom(&e, "alloc_failed").raw();
      }

      // Fill with 'A'
      char[]? slice = bin.as_mut_slice();
      if (catch err = slice) {
          bin.release();
          return term::make_error_atom(&e, "not_owned").raw();
      }
      for (usz i = 0; i < slice.len; i++) {
          slice[i] = 'A';
      }

      // Realloc to larger size
      if (catch err = bin.realloc((usz)final_size)) {
          bin.release();
          return term::make_error_atom(&e, "realloc_failed").raw();
      }

      // Fill new space with 'B'
      slice = bin.as_mut_slice()!!;
      for (usz i = initial; i < slice.len; i++) {
          slice[i] = 'B';
      }

      // Transfer
      term::Term? result = bin.to_term(&e);
      if (catch err = result) {
          bin.release();
          return term::make_error_atom(&e, "transfer_failed").raw();
      }

      return result.raw();
  }

  // =============================================================================
  // from_slice NIF
  // =============================================================================

  // NIF: echo_binary(binary) -> binary (tests from_slice convenience)
  fn erl_nif::ErlNifTerm echo_binary(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      binary::Binary? bin = binary::inspect(&e, arg);
      if (catch err = bin) {
          return term::make_badarg(&e).raw();
      }

      // Use from_slice to create a copy
      return binary::from_slice(&e, bin.as_slice()).raw();
  }

  // =============================================================================
  // NIF Entry
  // =============================================================================

  erl_nif::ErlNifFunc[10] nif_funcs = {
      { .name = "get_binary_size", .arity = 1, .fptr = &get_binary_size, .flags = 0 },
      { .name = "get_first_byte", .arity = 1, .fptr = &get_first_byte, .flags = 0 },
      { .name = "sum_bytes", .arity = 1, .fptr = &sum_bytes, .flags = 0 },
      { .name = "make_zeros", .arity = 1, .fptr = &make_zeros, .flags = 0 },
      { .name = "make_sequence", .arity = 1, .fptr = &make_sequence, .flags = 0 },
      { .name = "copy_binary", .arity = 1, .fptr = &copy_binary, .flags = 0 },
      { .name = "get_slice", .arity = 3, .fptr = &get_slice, .flags = 0 },
      { .name = "flatten_iolist", .arity = 1, .fptr = &flatten_iolist, .flags = 0 },
      { .name = "make_and_grow", .arity = 2, .fptr = &make_and_grow, .flags = 0 },
      { .name = "echo_binary", .arity = 1, .fptr = &echo_binary, .flags = 0 },
  };

  erl_nif::ErlNifEntry nif_entry;

  fn erl_nif::ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.BinaryNif",
          &nif_funcs,
          10,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.BinaryNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.BinaryNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.BinaryNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "binary inspection" do
    test "get_binary_size returns correct size" do
      assert C3nif.IntegrationTest.BinaryNif.get_binary_size(<<>>) == 0
      assert C3nif.IntegrationTest.BinaryNif.get_binary_size(<<1>>) == 1
      assert C3nif.IntegrationTest.BinaryNif.get_binary_size(<<1, 2, 3, 4, 5>>) == 5
      assert C3nif.IntegrationTest.BinaryNif.get_binary_size(:binary.copy(<<0>>, 1000)) == 1000
    end

    test "get_first_byte returns first byte or :empty" do
      assert C3nif.IntegrationTest.BinaryNif.get_first_byte(<<>>) == :empty
      assert C3nif.IntegrationTest.BinaryNif.get_first_byte(<<42>>) == 42
      assert C3nif.IntegrationTest.BinaryNif.get_first_byte(<<255, 1, 2>>) == 255
      assert C3nif.IntegrationTest.BinaryNif.get_first_byte(<<0, 99>>) == 0
    end

    test "sum_bytes sums all bytes" do
      assert C3nif.IntegrationTest.BinaryNif.sum_bytes(<<>>) == 0
      assert C3nif.IntegrationTest.BinaryNif.sum_bytes(<<1, 2, 3>>) == 6
      assert C3nif.IntegrationTest.BinaryNif.sum_bytes(<<255, 255>>) == 510
      assert C3nif.IntegrationTest.BinaryNif.sum_bytes(:binary.copy(<<1>>, 100)) == 100
    end

    test "get_binary_size raises on non-binary" do
      assert_raise ArgumentError, fn ->
        C3nif.IntegrationTest.BinaryNif.get_binary_size(:not_a_binary)
      end

      assert_raise ArgumentError, fn ->
        C3nif.IntegrationTest.BinaryNif.get_binary_size([1, 2, 3])
      end
    end
  end

  describe "binary allocation" do
    test "make_zeros creates zero-filled binary" do
      assert C3nif.IntegrationTest.BinaryNif.make_zeros(0) == <<>>
      assert C3nif.IntegrationTest.BinaryNif.make_zeros(1) == <<0>>
      assert C3nif.IntegrationTest.BinaryNif.make_zeros(5) == <<0, 0, 0, 0, 0>>
    end

    test "make_sequence creates sequential bytes" do
      assert C3nif.IntegrationTest.BinaryNif.make_sequence(0) == <<>>
      assert C3nif.IntegrationTest.BinaryNif.make_sequence(3) == <<0, 1, 2>>
      assert C3nif.IntegrationTest.BinaryNif.make_sequence(256) == :binary.list_to_bin(Enum.to_list(0..255))
    end

    test "copy_binary creates independent copy" do
      original = <<1, 2, 3, 4, 5>>
      copy = C3nif.IntegrationTest.BinaryNif.copy_binary(original)
      assert copy == original
      # Verify they're different binaries (same content)
      assert :binary.referenced_byte_size(copy) == 5
    end
  end

  describe "sub-binary (zero-copy slice)" do
    test "get_slice returns sub-binary" do
      bin = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
      assert C3nif.IntegrationTest.BinaryNif.get_slice(bin, 0, 3) == <<0, 1, 2>>
      assert C3nif.IntegrationTest.BinaryNif.get_slice(bin, 5, 3) == <<5, 6, 7>>
      assert C3nif.IntegrationTest.BinaryNif.get_slice(bin, 0, 10) == bin
    end

    test "get_slice with empty range" do
      bin = <<1, 2, 3>>
      assert C3nif.IntegrationTest.BinaryNif.get_slice(bin, 0, 0) == <<>>
      assert C3nif.IntegrationTest.BinaryNif.get_slice(bin, 3, 0) == <<>>
    end
  end

  describe "iolist flattening" do
    test "flatten_iolist handles simple binary" do
      assert C3nif.IntegrationTest.BinaryNif.flatten_iolist(<<1, 2, 3>>) == {:ok, 3, 1}
    end

    test "flatten_iolist handles nested iolist" do
      iolist = [<<1>>, [<<2>>, <<3>>]]
      assert C3nif.IntegrationTest.BinaryNif.flatten_iolist(iolist) == {:ok, 3, 1}
    end

    test "flatten_iolist handles charlist" do
      charlist = ~c"hello"
      {:ok, size, first} = C3nif.IntegrationTest.BinaryNif.flatten_iolist(charlist)
      assert size == 5
      assert first == ?h
    end

    test "flatten_iolist handles empty" do
      assert C3nif.IntegrationTest.BinaryNif.flatten_iolist([]) == {:ok, 0, 0}
      assert C3nif.IntegrationTest.BinaryNif.flatten_iolist(<<>>) == {:ok, 0, 0}
    end
  end

  describe "binary reallocation" do
    test "make_and_grow allocates and grows" do
      result = C3nif.IntegrationTest.BinaryNif.make_and_grow(3, 6)
      assert result == <<"AAABBB">>
    end

    test "make_and_grow with same size" do
      result = C3nif.IntegrationTest.BinaryNif.make_and_grow(5, 5)
      assert result == <<"AAAAA">>
    end

    test "make_and_grow from zero" do
      result = C3nif.IntegrationTest.BinaryNif.make_and_grow(0, 3)
      assert result == <<"BBB">>
    end
  end

  describe "from_slice convenience" do
    test "echo_binary creates copy via from_slice" do
      original = <<10, 20, 30, 40, 50>>
      copy = C3nif.IntegrationTest.BinaryNif.echo_binary(original)
      assert copy == original
    end

    test "echo_binary handles empty binary" do
      assert C3nif.IntegrationTest.BinaryNif.echo_binary(<<>>) == <<>>
    end

    test "echo_binary handles large binary" do
      large = :binary.copy(<<42>>, 10_000)
      copy = C3nif.IntegrationTest.BinaryNif.echo_binary(large)
      assert copy == large
    end
  end

  describe "heap vs refc binary threshold" do
    test "small binaries (heap) work correctly" do
      # Heap binaries are <= 64 bytes
      small = :binary.copy(<<1>>, 64)
      assert C3nif.IntegrationTest.BinaryNif.get_binary_size(small) == 64
      assert C3nif.IntegrationTest.BinaryNif.copy_binary(small) == small
    end

    test "large binaries (refc) work correctly" do
      # Refc binaries are > 64 bytes
      large = :binary.copy(<<2>>, 65)
      assert C3nif.IntegrationTest.BinaryNif.get_binary_size(large) == 65
      assert C3nif.IntegrationTest.BinaryNif.copy_binary(large) == large
    end

    test "very large binaries work correctly" do
      very_large = :binary.copy(<<3>>, 100_000)
      assert C3nif.IntegrationTest.BinaryNif.get_binary_size(very_large) == 100_000
      assert C3nif.IntegrationTest.BinaryNif.sum_bytes(very_large) == 300_000
    end
  end
end
