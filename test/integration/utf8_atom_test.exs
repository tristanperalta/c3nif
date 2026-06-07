# Test coverage for ERL_NIF 2.17 UTF-8 atom creation helpers.
# Requires OTP 26+ (ERL_NIF 2.17).
defmodule C3nif.IntegrationTest.Utf8AtomNif do
  @nif_path_base "libC3nif.IntegrationTest.Utf8AtomNif"

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

  def make_utf8(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def make_utf8_cstr(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def make_existing_utf8(_binary), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.Utf8AtomTest do
  use C3nif.Case, async: false

  alias C3nif.IntegrationTest.Utf8AtomNif

  @moduletag :integration

  @c3_code """
  module utf8_atom_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  // NIF: make_utf8(binary) -> atom | {:error, :atom_table_full}
  fn ErlNifTerm make_utf8(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term bin_term = term::wrap(argv[0]);

      ErlNifBinary? bin = bin_term.inspect_binary(&e);
      if (catch err = bin) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      if (bin.size > 255) {
          return term::make_error_atom(&e, "too_long").raw();
      }

      Term? atom = term::make_atom_len(&e, (char*)bin.data, (usz)bin.size);
      if (catch err = atom) {
          return term::make_error_atom(&e, "atom_table_full").raw();
      }
      return atom.raw();
  }

  // NIF: make_utf8_cstr(binary) -> atom | {:error, :atom_table_full}
  // Exercises the no-length make_atom default (safe UTF-8).
  fn ErlNifTerm make_utf8_cstr(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term bin_term = term::wrap(argv[0]);

      ErlNifBinary? bin = bin_term.inspect_binary(&e);
      if (catch err = bin) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      if (bin.size > 255) {
          return term::make_error_atom(&e, "too_long").raw();
      }

      char[256] buf;
      for (usz i = 0; i < bin.size; i++) {
          buf[i] = bin.data[i];
      }
      buf[bin.size] = 0;

      Term? atom = term::make_atom(&e, &buf);
      if (catch err = atom) {
          return term::make_error_atom(&e, "atom_table_full").raw();
      }
      return atom.raw();
  }

  // NIF: make_existing_utf8(binary) -> {:ok, atom} | {:error, :not_found}
  fn ErlNifTerm make_existing_utf8(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term bin_term = term::wrap(argv[0]);

      ErlNifBinary? bin = bin_term.inspect_binary(&e);
      if (catch err = bin) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      if (bin.size > 255) {
          return term::make_error_atom(&e, "too_long").raw();
      }

      char[256] buf;
      for (usz i = 0; i < bin.size; i++) {
          buf[i] = bin.data[i];
      }
      buf[bin.size] = 0;

      Term? atom = term::make_existing_atom_utf8(&e, &buf);
      if (catch err = atom) {
          return term::make_error_atom(&e, "not_found").raw();
      }
      return term::make_ok_tuple(&e, atom).raw();
  }

  ErlNifFunc[3] nif_funcs = {
      { .name = "make_utf8", .arity = 1, .fptr = &make_utf8, .flags = 0 },
      { .name = "make_utf8_cstr", .arity = 1, .fptr = &make_utf8_cstr, .flags = 0 },
      { .name = "make_existing_utf8", .arity = 1, .fptr = &make_existing_utf8, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.Utf8AtomNif",
          &nif_funcs,
          3,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.Utf8AtomNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.Utf8AtomNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case Utf8AtomNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "make_atom_len" do
    test "creates ASCII atoms" do
      assert Utf8AtomNif.make_utf8("hello") == :hello
    end

    test "creates non-Latin-1 UTF-8 atoms" do
      # U+1F600 GRINNING FACE + Japanese 日本
      assert Utf8AtomNif.make_utf8("日本") == :"日本"
      assert Utf8AtomNif.make_utf8("café") == :"café"
    end

    test "creates empty atom" do
      assert Utf8AtomNif.make_utf8("") == :""
    end
  end

  describe "make_atom (no-length default)" do
    test "creates ASCII atoms" do
      assert Utf8AtomNif.make_utf8_cstr("hello") == :hello
    end

    test "creates non-Latin-1 UTF-8 atoms" do
      assert Utf8AtomNif.make_utf8_cstr("日本") == :"日本"
      assert Utf8AtomNif.make_utf8_cstr("café") == :"café"
    end
  end

  describe "make_existing_atom_utf8" do
    test "finds a UTF-8 atom that already exists" do
      # Ensure the atom exists first by creating it via the NIF.
      _ = Utf8AtomNif.make_utf8("prewarmed_utf8_atom")
      assert Utf8AtomNif.make_existing_utf8("prewarmed_utf8_atom") ==
               {:ok, :prewarmed_utf8_atom}
    end

    test "returns :not_found for missing UTF-8 atom" do
      # Random unicode atom that shouldn't exist
      assert Utf8AtomNif.make_existing_utf8("未登録_#{System.unique_integer([:positive])}") ==
               {:error, :not_found}
    end
  end
end
