# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.CodegenTestNif do
  @nif_path_base "libC3nif.IntegrationTest.CodegenTestNif"

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

  # Manual stubs - Rustler style
  def add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def custom_name(_a), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.CodegenTest do
  use C3nif.Case, async: false

  @moduletag :integration

  # C3 code with nif: annotations - NO manual entry point!
  # The entry point should be auto-generated.
  @c3_code """
  module codegen_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  <* nif: arity = 2 *>
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

  <* nif: name = "custom_name", arity = 1 *>
  fn erl_nif::ErlNifTerm internal_echo(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      return argv[0];
  }
  """

  setup_all do
    # Compile with automatic code generation (skip_codegen: false)
    case compile_test_nif(
           C3nif.IntegrationTest.CodegenTestNif,
           @c3_code,
           otp_app: :c3nif,
           skip_codegen: false
         ) do
      {:ok, lib_path} ->
        # Copy to priv directory for loading
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.CodegenTestNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        # Load the NIF
        case C3nif.IntegrationTest.CodegenTestNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "auto-generated entry point" do
    test "add/2 works with auto-generated entry" do
      assert C3nif.IntegrationTest.CodegenTestNif.add(1, 2) == 3
      assert C3nif.IntegrationTest.CodegenTestNif.add(-5, 10) == 5
      assert C3nif.IntegrationTest.CodegenTestNif.add(100, 200) == 300
    end

    test "add/2 raises on non-integer" do
      assert_raise ArgumentError, fn ->
        C3nif.IntegrationTest.CodegenTestNif.add("a", 1)
      end
    end

    test "custom_name/1 calls internal_echo via custom name" do
      assert C3nif.IntegrationTest.CodegenTestNif.custom_name(42) == 42
      assert C3nif.IntegrationTest.CodegenTestNif.custom_name(:hello) == :hello
      assert C3nif.IntegrationTest.CodegenTestNif.custom_name([1, 2, 3]) == [1, 2, 3]
    end
  end
end

# Separate test for on_load callback detection
defmodule C3nif.IntegrationTest.CodegenWithCallbackNif do
  @nif_path_base "libC3nif.IntegrationTest.CodegenWithCallbackNif"

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

  def get_counter, do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.CodegenWithCallbackTest do
  use C3nif.Case, async: false

  @moduletag :integration

  # C3 code with on_load callback that should be auto-detected
  @c3_code """
  module codegen_callback_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  // Global counter to verify on_load was called
  int load_counter = 0;

  // on_load callback - should be auto-detected by function name
  fn CInt on_load(erl_nif::ErlNifEnv* raw_env, void** priv, erl_nif::ErlNifTerm load_info) {
      load_counter = 42;
      return 0;
  }

  <* nif: arity = 0 *>
  fn erl_nif::ErlNifTerm get_counter(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      return term::make_int(&e, load_counter).raw();
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.CodegenWithCallbackNif,
           @c3_code,
           otp_app: :c3nif,
           skip_codegen: false
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.CodegenWithCallbackNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.CodegenWithCallbackNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "auto-detected on_load callback" do
    test "on_load was called during NIF loading" do
      # If on_load was properly detected and wired up, load_counter should be 42
      assert C3nif.IntegrationTest.CodegenWithCallbackNif.get_counter() == 42
    end
  end
end

# Test for dirty scheduler annotations in codegen
defmodule C3nif.IntegrationTest.CodegenDirtySchedulerNif do
  @nif_path_base "libC3nif.IntegrationTest.CodegenDirtySchedulerNif"

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

  # Manual stubs
  def dirty_cpu_annotated, do: :erlang.nif_error(:nif_not_loaded)
  def dirty_io_annotated, do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.CodegenDirtySchedulerTest do
  use C3nif.Case, async: false

  @moduletag :integration

  # C3 code with dirty scheduler annotations - entry point auto-generated
  @c3_code """
  module codegen_dirty_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::scheduler;

  <* nif: arity = 0, dirty = cpu *>
  fn erl_nif::ErlNifTerm dirty_cpu_annotated(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      scheduler::ThreadType t = scheduler::current_thread_type();

      char* thread_name;
      switch (t) {
          case scheduler::ThreadType.DIRTY_CPU: thread_name = "dirty_cpu";
          case scheduler::ThreadType.DIRTY_IO: thread_name = "dirty_io";
          case scheduler::ThreadType.NORMAL: thread_name = "normal";
          case scheduler::ThreadType.UNDEFINED: thread_name = "undefined";
      }

      return term::make_ok_tuple(&e, term::make_atom(&e, thread_name)).raw();
  }

  <* nif: arity = 0, dirty = io *>
  fn erl_nif::ErlNifTerm dirty_io_annotated(
      erl_nif::ErlNifEnv* raw_env,
      CInt argc,
      erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(raw_env);
      scheduler::ThreadType t = scheduler::current_thread_type();

      char* thread_name;
      switch (t) {
          case scheduler::ThreadType.DIRTY_CPU: thread_name = "dirty_cpu";
          case scheduler::ThreadType.DIRTY_IO: thread_name = "dirty_io";
          case scheduler::ThreadType.NORMAL: thread_name = "normal";
          case scheduler::ThreadType.UNDEFINED: thread_name = "undefined";
      }

      return term::make_ok_tuple(&e, term::make_atom(&e, thread_name)).raw();
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.CodegenDirtySchedulerNif,
           @c3_code,
           otp_app: :c3nif,
           skip_codegen: false
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.CodegenDirtySchedulerNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.CodegenDirtySchedulerNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "dirty scheduler annotations in codegen" do
    test "dirty = cpu annotation runs NIF on dirty CPU scheduler" do
      assert {:ok, :dirty_cpu} = C3nif.IntegrationTest.CodegenDirtySchedulerNif.dirty_cpu_annotated()
    end

    test "dirty = io annotation runs NIF on dirty IO scheduler" do
      assert {:ok, :dirty_io} = C3nif.IntegrationTest.CodegenDirtySchedulerNif.dirty_io_annotated()
    end
  end
end
