# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.TestNif do
  @nif_path_base "libC3nif.IntegrationTest.TestNif"

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

  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def echo(_term), do: :erlang.nif_error(:nif_not_loaded)
  def make_ok(_value), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.NifLoadingTest do
  use C3nif.Case, async: false

  @moduletag :integration

  @c3_code """
  module test_nif;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  // Simple add function: add(a, b) -> a + b
  fn erl_nif::ErlNifTerm add(
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

      return term::make_int(&e, val0 + val1).raw();
  }

  // Echo function: echo(term) -> term
  fn erl_nif::ErlNifTerm echo(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      return argv[0];
  }

  // Return ok tuple: make_ok(value) -> {:ok, value}
  fn erl_nif::ErlNifTerm make_ok(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      term::Term arg = term::wrap(argv[0]);
      return term::make_ok_tuple(&e, arg).raw();
  }

  // NIF function table
  erl_nif::ErlNifFunc[3] nif_funcs = {
      { .name = "add", .arity = 2, .fptr = &add, .flags = 0 },
      { .name = "echo", .arity = 1, .fptr = &echo, .flags = 0 },
      { .name = "make_ok", .arity = 1, .fptr = &make_ok, .flags = 0 },
  };

  // Static entry - must persist beyond nif_init call
  erl_nif::ErlNifEntry nif_entry;

  // Entry point - called by BEAM to get NIF info
  fn erl_nif::ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.TestNif",
          &nif_funcs,
          3,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    # Compile the test NIF once for all tests
    case compile_test_nif(
           C3nif.IntegrationTest.TestNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        # Copy to priv directory for loading
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.TestNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        # Load the NIF
        case C3nif.IntegrationTest.TestNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "NIF loading and execution" do
    test "add/2 adds two integers" do
      assert C3nif.IntegrationTest.TestNif.add(1, 2) == 3
      assert C3nif.IntegrationTest.TestNif.add(-5, 10) == 5
      assert C3nif.IntegrationTest.TestNif.add(0, 0) == 0
    end

    test "add/2 raises on non-integer" do
      assert_raise ArgumentError, fn -> C3nif.IntegrationTest.TestNif.add("a", 1) end
      assert_raise ArgumentError, fn -> C3nif.IntegrationTest.TestNif.add(1, :atom) end
    end

    test "echo/1 returns the argument unchanged" do
      assert C3nif.IntegrationTest.TestNif.echo(42) == 42
      assert C3nif.IntegrationTest.TestNif.echo(:hello) == :hello
      assert C3nif.IntegrationTest.TestNif.echo([1, 2, 3]) == [1, 2, 3]
    end

    test "make_ok/1 wraps value in ok tuple" do
      assert C3nif.IntegrationTest.TestNif.make_ok(42) == {:ok, 42}
      assert C3nif.IntegrationTest.TestNif.make_ok(:done) == {:ok, :done}
    end
  end
end
