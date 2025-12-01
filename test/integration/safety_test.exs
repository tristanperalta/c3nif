# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.SafetyNif do
  @nif_path_base "libC3nif.IntegrationTest.SafetyNif"

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

  # Argument validation tests
  def get_int(_value), do: :erlang.nif_error(:nif_not_loaded)
  def get_two_ints(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def require_positive(_value), do: :erlang.nif_error(:nif_not_loaded)
  def require_range(_value, _min, _max), do: :erlang.nif_error(:nif_not_loaded)

  # Fault barrier tests
  def safe_divide(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def nested_faults(_value), do: :erlang.nif_error(:nif_not_loaded)

  # Type validation tests
  def require_atom_test(_value), do: :erlang.nif_error(:nif_not_loaded)
  def require_list_test(_value), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.SafetyTest do
  use C3nif.Case, async: false

  @moduletag :integration

  @c3_code """
  module safety_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::safety;

  // =============================================================================
  // Basic Argument Extraction with Fault Barrier
  // =============================================================================

  // NIF: get_int(value) -> {:ok, value} | {:error, :badarg}
  fn ErlNifTerm get_int(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg = safety::get_arg(argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      int? value = safety::require_int(&e, arg);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_int(&e, value)).raw();
  }

  // =============================================================================
  // Multiple Arguments
  // =============================================================================

  // NIF: get_two_ints(a, b) -> {:ok, sum} | {:error, :badarg}
  fn ErlNifTerm get_two_ints(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg0 = safety::get_arg(argv, argc, 0);
      if (catch err = arg0) {
          return safety::make_badarg_error(&e).raw();
      }

      Term? arg1 = safety::get_arg(argv, argc, 1);
      if (catch err = arg1) {
          return safety::make_badarg_error(&e).raw();
      }

      int? a = safety::require_int(&e, arg0);
      if (catch err = a) {
          return safety::make_badarg_error(&e).raw();
      }

      int? b = safety::require_int(&e, arg1);
      if (catch err = b) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_int(&e, a + b)).raw();
  }

  // =============================================================================
  // Range Validation
  // =============================================================================

  // NIF: require_positive(value) -> {:ok, value} | {:error, :badarg}
  fn ErlNifTerm require_positive(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg = safety::get_arg(argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      int? value = safety::require_positive(&e, arg);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_int(&e, value)).raw();
  }

  // NIF: require_range(value, min, max) -> {:ok, value} | {:error, :badarg}
  fn ErlNifTerm require_range(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg = safety::get_arg(argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      Term? min_arg = safety::get_arg(argv, argc, 1);
      if (catch err = min_arg) {
          return safety::make_badarg_error(&e).raw();
      }

      Term? max_arg = safety::get_arg(argv, argc, 2);
      if (catch err = max_arg) {
          return safety::make_badarg_error(&e).raw();
      }

      int? min = safety::require_int(&e, min_arg);
      if (catch err = min) {
          return safety::make_badarg_error(&e).raw();
      }

      int? max = safety::require_int(&e, max_arg);
      if (catch err = max) {
          return safety::make_badarg_error(&e).raw();
      }

      int? value = safety::require_int_range(&e, arg, min, max);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_int(&e, value)).raw();
  }

  // =============================================================================
  // Division with Custom Error Handling
  // =============================================================================

  faultdef DIVIDE_BY_ZERO;

  // NIF: safe_divide(a, b) -> {:ok, result} | {:error, :badarg} | {:error, :divide_by_zero}
  fn ErlNifTerm safe_divide(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg0 = safety::get_arg(argv, argc, 0);
      if (catch err = arg0) {
          return safety::make_badarg_error(&e).raw();
      }

      Term? arg1 = safety::get_arg(argv, argc, 1);
      if (catch err = arg1) {
          return safety::make_badarg_error(&e).raw();
      }

      int? a = safety::require_int(&e, arg0);
      if (catch err = a) {
          return safety::make_badarg_error(&e).raw();
      }

      int? b = safety::require_int(&e, arg1);
      if (catch err = b) {
          return safety::make_badarg_error(&e).raw();
      }

      if (b == 0) {
          return term::make_error_atom(&e, "divide_by_zero").raw();
      }

      return term::make_ok_tuple(&e, term::make_int(&e, a / b)).raw();
  }

  // =============================================================================
  // Nested Fault Propagation
  // =============================================================================

  fn int? helper_double(int value) {
      if (value > 1000000) {
          return term::OVERFLOW?;
      }
      return value * 2;
  }

  // NIF: nested_faults(value) -> {:ok, doubled} | {:error, :badarg} | {:error, :overflow}
  fn ErlNifTerm nested_faults(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg = safety::get_arg(argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      int? value = safety::require_int(&e, arg);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      int? doubled = helper_double(value);
      if (catch err = doubled) {
          if (err == term::OVERFLOW) {
              return safety::make_overflow_error(&e).raw();
          }
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_int(&e, doubled)).raw();
  }

  // =============================================================================
  // Type Validation
  // =============================================================================

  // NIF: require_atom_test(value) -> :ok | {:error, :badarg}
  fn ErlNifTerm require_atom_test(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg = safety::get_arg(argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      if (catch err = safety::require_atom(&e, arg)) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_atom(&e, "ok").raw();
  }

  // NIF: require_list_test(value) -> :ok | {:error, :badarg}
  fn ErlNifTerm require_list_test(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg = safety::get_arg(argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      if (catch err = safety::require_list(&e, arg)) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_atom(&e, "ok").raw();
  }

  // =============================================================================
  // NIF Entry
  // =============================================================================

  ErlNifFunc[8] nif_funcs = {
      { .name = "get_int", .arity = 1, .fptr = &get_int, .flags = 0 },
      { .name = "get_two_ints", .arity = 2, .fptr = &get_two_ints, .flags = 0 },
      { .name = "require_positive", .arity = 1, .fptr = &require_positive, .flags = 0 },
      { .name = "require_range", .arity = 3, .fptr = &require_range, .flags = 0 },
      { .name = "safe_divide", .arity = 2, .fptr = &safe_divide, .flags = 0 },
      { .name = "nested_faults", .arity = 1, .fptr = &nested_faults, .flags = 0 },
      { .name = "require_atom_test", .arity = 1, .fptr = &require_atom_test, .flags = 0 },
      { .name = "require_list_test", .arity = 1, .fptr = &require_list_test, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.SafetyNif",
          &nif_funcs,
          8,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.SafetyNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.SafetyNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.SafetyNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "basic argument extraction" do
    test "get_int with valid integer returns {:ok, value}" do
      assert C3nif.IntegrationTest.SafetyNif.get_int(42) == {:ok, 42}
    end

    test "get_int with negative integer returns {:ok, value}" do
      assert C3nif.IntegrationTest.SafetyNif.get_int(-100) == {:ok, -100}
    end

    test "get_int with non-integer returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.get_int("not an int") == {:error, :badarg}
    end

    test "get_int with atom returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.get_int(:atom) == {:error, :badarg}
    end

    test "get_int with float returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.get_int(3.14) == {:error, :badarg}
    end
  end

  describe "multiple argument extraction" do
    test "get_two_ints with valid integers returns sum" do
      assert C3nif.IntegrationTest.SafetyNif.get_two_ints(10, 20) == {:ok, 30}
    end

    test "get_two_ints with first arg invalid returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.get_two_ints("a", 20) == {:error, :badarg}
    end

    test "get_two_ints with second arg invalid returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.get_two_ints(10, "b") == {:error, :badarg}
    end
  end

  describe "range validation" do
    test "require_positive with positive value succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.require_positive(42) == {:ok, 42}
    end

    test "require_positive with zero returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.require_positive(0) == {:error, :badarg}
    end

    test "require_positive with negative returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.require_positive(-5) == {:error, :badarg}
    end

    test "require_range with value in range succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.require_range(50, 0, 100) == {:ok, 50}
    end

    test "require_range at min boundary succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.require_range(0, 0, 100) == {:ok, 0}
    end

    test "require_range at max boundary succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.require_range(100, 0, 100) == {:ok, 100}
    end

    test "require_range below min returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.require_range(-1, 0, 100) == {:error, :badarg}
    end

    test "require_range above max returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.require_range(101, 0, 100) == {:error, :badarg}
    end
  end

  describe "custom fault handling" do
    test "safe_divide with valid division succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.safe_divide(10, 2) == {:ok, 5}
    end

    test "safe_divide by zero returns {:error, :divide_by_zero}" do
      assert C3nif.IntegrationTest.SafetyNif.safe_divide(10, 0) == {:error, :divide_by_zero}
    end

    test "safe_divide with invalid first arg returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.safe_divide("a", 2) == {:error, :badarg}
    end
  end

  describe "nested fault propagation" do
    test "nested_faults with small value succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.nested_faults(100) == {:ok, 200}
    end

    test "nested_faults with large value returns {:error, :overflow}" do
      assert C3nif.IntegrationTest.SafetyNif.nested_faults(2_000_000) == {:error, :overflow}
    end

    test "nested_faults with invalid input returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.nested_faults(:not_int) == {:error, :badarg}
    end
  end

  describe "type validation" do
    test "require_atom_test with atom succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.require_atom_test(:hello) == :ok
    end

    test "require_atom_test with non-atom returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.require_atom_test(123) == {:error, :badarg}
    end

    test "require_list_test with list succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.require_list_test([1, 2, 3]) == :ok
    end

    test "require_list_test with empty list succeeds" do
      assert C3nif.IntegrationTest.SafetyNif.require_list_test([]) == :ok
    end

    test "require_list_test with non-list returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.SafetyNif.require_list_test(:not_a_list) == {:error, :badarg}
    end
  end
end
