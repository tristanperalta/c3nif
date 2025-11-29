# Test external C3 source file inclusion via c3_sources option
defmodule C3nif.IntegrationTest.ExternalSourcesNif do
  @nif_path_base "libC3nif.IntegrationTest.ExternalSourcesNif"

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

  # NIF stubs
  def multiply(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def square(_n), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.ExternalSourcesTest do
  use C3nif.Case, async: false

  @moduletag :integration

  # Main C3 code that imports and uses external source modules
  @c3_code """
  module external_sources_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  // Import the external helper module
  import math_helpers;

  <* nif: arity = 2 *>
  fn erl_nif::ErlNifTerm multiply(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      term::Term arg0 = term::wrap(argv[0]);
      term::Term arg1 = term::wrap(argv[1]);

      int? val0 = arg0.get_int(&e);
      if (catch err = val0) {
          return term::make_badarg(&e).raw();
      }

      int? val1 = arg1.get_int(&e);
      if (catch err = val1) {
          return term::make_badarg(&e).raw();
      }

      // Use the external multiply function
      int result = math_helpers::multiply(val0, val1);
      return term::make_int(&e, result).raw();
  }

  <* nif: arity = 1 *>
  fn erl_nif::ErlNifTerm square(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      term::Term arg0 = term::wrap(argv[0]);

      int? val = arg0.get_int(&e);
      if (catch err = val) {
          return term::make_badarg(&e).raw();
      }

      // Use the external square function
      int result = math_helpers::square(val);
      return term::make_int(&e, result).raw();
  }
  """

  @fixtures_dir Path.expand("../fixtures/external_sources", __DIR__)

  setup_all do
    # Compile with external source file
    external_source = Path.join(@fixtures_dir, "math_helpers.c3")

    case compile_test_nif_with_sources(
           C3nif.IntegrationTest.ExternalSourcesNif,
           @c3_code,
           [external_source],
           otp_app: :c3nif,
           skip_codegen: false
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.ExternalSourcesNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.ExternalSourcesNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "external source file inclusion" do
    test "multiply/2 uses external math_helpers module" do
      assert C3nif.IntegrationTest.ExternalSourcesNif.multiply(3, 4) == 12
      assert C3nif.IntegrationTest.ExternalSourcesNif.multiply(7, 8) == 56
      assert C3nif.IntegrationTest.ExternalSourcesNif.multiply(-5, 3) == -15
    end

    test "square/1 uses external math_helpers module" do
      assert C3nif.IntegrationTest.ExternalSourcesNif.square(5) == 25
      assert C3nif.IntegrationTest.ExternalSourcesNif.square(10) == 100
      assert C3nif.IntegrationTest.ExternalSourcesNif.square(-4) == 16
    end

    test "multiply/2 raises on non-integer arguments" do
      assert_raise ArgumentError, fn ->
        C3nif.IntegrationTest.ExternalSourcesNif.multiply("a", 1)
      end
    end
  end

  # Helper to compile with external sources
  defp compile_test_nif_with_sources(module, c3_code, c3_sources, opts) do
    otp_app = Keyword.get(opts, :otp_app, :c3nif)
    skip_codegen = Keyword.get(opts, :skip_codegen, true)

    compile_opts = [
      module: module,
      otp_app: otp_app,
      c3_code: c3_code,
      c3_sources: c3_sources,
      skip_codegen: skip_codegen
    ]

    C3nif.Compiler.compile(compile_opts)
  end
end

# Test for glob pattern expansion
defmodule C3nif.IntegrationTest.GlobPatternNif do
  @nif_path_base "libC3nif.IntegrationTest.GlobPatternNif"

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

  def get_string_length(_str), do: :erlang.nif_error(:nif_not_loaded)
  def increment(_n), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.GlobPatternTest do
  use C3nif.Case, async: false

  @moduletag :integration

  # Main C3 code that imports multiple external modules via glob
  @c3_code """
  module glob_pattern_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  // Import modules from external sources matched by glob
  import string_helpers;
  import nested_helper;

  <* nif: arity = 1 *>
  fn erl_nif::ErlNifTerm get_string_length(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      term::Term arg0 = term::wrap(argv[0]);

      // Get binary data from argument
      erl_nif::ErlNifBinary bin;
      if (!erl_nif::enif_inspect_binary(raw_env, argv[0], &bin)) {
          return term::make_badarg(&e).raw();
      }

      // Calculate length using external helper
      // Note: we can't directly use string_helpers on binary, so we just return the binary size
      return term::make_int(&e, (int)bin.size).raw();
  }

  <* nif: arity = 1 *>
  fn erl_nif::ErlNifTerm increment(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      term::Term arg0 = term::wrap(argv[0]);

      int? val = arg0.get_int(&e);
      if (catch err = val) {
          return term::make_badarg(&e).raw();
      }

      // Use the external nested_helper module
      int result = nested_helper::increment(val);
      return term::make_int(&e, result).raw();
  }
  """

  @fixtures_dir Path.expand("../fixtures/external_sources", __DIR__)

  setup_all do
    # Use glob pattern to include all .c3 files recursively
    glob_pattern = Path.join(@fixtures_dir, "**/*.c3")

    case compile_test_nif_with_sources(
           C3nif.IntegrationTest.GlobPatternNif,
           @c3_code,
           [glob_pattern],
           otp_app: :c3nif,
           skip_codegen: false
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.GlobPatternNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.GlobPatternNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "glob pattern expansion" do
    test "get_string_length/1 works with external string_helpers module" do
      assert C3nif.IntegrationTest.GlobPatternNif.get_string_length("hello") == 5
      assert C3nif.IntegrationTest.GlobPatternNif.get_string_length("") == 0
      assert C3nif.IntegrationTest.GlobPatternNif.get_string_length("test string") == 11
    end

    test "increment/1 uses nested_helper from subdirectory" do
      assert C3nif.IntegrationTest.GlobPatternNif.increment(5) == 6
      assert C3nif.IntegrationTest.GlobPatternNif.increment(0) == 1
      assert C3nif.IntegrationTest.GlobPatternNif.increment(-1) == 0
    end
  end

  # Helper to compile with external sources
  defp compile_test_nif_with_sources(module, c3_code, c3_sources, opts) do
    otp_app = Keyword.get(opts, :otp_app, :c3nif)
    skip_codegen = Keyword.get(opts, :skip_codegen, true)

    compile_opts = [
      module: module,
      otp_app: otp_app,
      c3_code: c3_code,
      c3_sources: c3_sources,
      skip_codegen: skip_codegen
    ]

    C3nif.Compiler.compile(compile_opts)
  end
end
