# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.MacrosNif do
  @nif_path_base "libC3nif.IntegrationTest.MacrosNif"

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

  # @nif_entry macro tests
  def add_with_macro(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def add_with_custom_error(_a, _b), do: :erlang.nif_error(:nif_not_loaded)

  # @require_arg_* macro tests
  def require_arg_int_test(_value), do: :erlang.nif_error(:nif_not_loaded)
  def require_arg_long_test(_value), do: :erlang.nif_error(:nif_not_loaded)
  def require_arg_double_test(_value), do: :erlang.nif_error(:nif_not_loaded)
  def require_arg_uint_test(_value), do: :erlang.nif_error(:nif_not_loaded)

  # @require_type macro tests
  def require_atom_macro(_value), do: :erlang.nif_error(:nif_not_loaded)
  def require_list_macro(_value), do: :erlang.nif_error(:nif_not_loaded)
  def require_map_macro(_value), do: :erlang.nif_error(:nif_not_loaded)

  # @get_resource macro tests (requires resource setup)
  def create_counter(), do: :erlang.nif_error(:nif_not_loaded)
  def get_counter_value(_resource), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.MacrosTest do
  use C3nif.Case, async: false

  @moduletag :integration

  @c3_code """
  module macros_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::safety;
  import c3nif::resource;
  import c3nif::macros;

  // =============================================================================
  // @nif_entry Macro Tests
  // =============================================================================

  // Implementation function for @nif_entry
  fn term::Term? add_impl(env::Env* e, erl_nif::ErlNifTerm* argv, CInt argc) {
      int a = macros::@require_arg_int(e, argv, argc, 0)!;
      int b = macros::@require_arg_int(e, argv, argc, 1)!;
      return term::make_int(e, a + b);
  }

  // NIF using nif_entry macro
  fn erl_nif::ErlNifTerm add_with_macro(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      return macros::nif_entry(env_raw, argc, argv, &add_impl);
  }

  // Implementation with intentional failure for custom error test
  fn term::Term? add_with_custom_error_impl(env::Env* e, erl_nif::ErlNifTerm* argv, CInt argc) {
      int a = macros::@require_arg_int(e, argv, argc, 0)!;
      int b = macros::@require_arg_int(e, argv, argc, 1)!;
      return term::make_int(e, a + b);
  }

  // NIF using nif_entry with custom error reason
  fn erl_nif::ErlNifTerm add_with_custom_error(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      return macros::nif_entry(env_raw, argc, argv, &add_with_custom_error_impl, "custom_error");
  }

  // =============================================================================
  // @require_arg_* Macro Tests
  // =============================================================================

  fn erl_nif::ErlNifTerm require_arg_int_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      int? value = macros::@require_arg_int(&e, argv, argc, 0);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_int(&e, value)).raw();
  }

  fn erl_nif::ErlNifTerm require_arg_long_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      long? value = macros::@require_arg_long(&e, argv, argc, 0);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_long(&e, value)).raw();
  }

  fn erl_nif::ErlNifTerm require_arg_double_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      double? value = macros::@require_arg_double(&e, argv, argc, 0);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_double(&e, value)).raw();
  }

  fn erl_nif::ErlNifTerm require_arg_uint_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      uint? value = macros::@require_arg_uint(&e, argv, argc, 0);
      if (catch err = value) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_ok_tuple(&e, term::make_uint(&e, value)).raw();
  }

  // =============================================================================
  // @require_type Macro Tests
  // =============================================================================

  fn erl_nif::ErlNifTerm require_atom_macro(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      term::Term? arg = macros::@require_arg(&e, argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      if (catch err = macros::@require_type(arg, is_atom, &e)) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_atom(&e, "ok").raw();
  }

  fn erl_nif::ErlNifTerm require_list_macro(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      term::Term? arg = macros::@require_arg(&e, argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      if (catch err = macros::@require_type(arg, is_list, &e)) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_atom(&e, "ok").raw();
  }

  fn erl_nif::ErlNifTerm require_map_macro(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      term::Term? arg = macros::@require_arg(&e, argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      if (catch err = macros::@require_type(arg, is_map, &e)) {
          return safety::make_badarg_error(&e).raw();
      }

      return term::make_atom(&e, "ok").raw();
  }

  // =============================================================================
  // @get_resource Macro Tests
  // =============================================================================

  struct Counter {
      int value;
  }

  erl_nif::ErlNifResourceType* counter_resource_type;

  fn erl_nif::ErlNifTerm create_counter(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      void* ptr = erl_nif::enif_alloc_resource(counter_resource_type, Counter.sizeof);
      if (ptr == null) {
          return safety::make_alloc_error(&e).raw();
      }

      Counter* counter = (Counter*)ptr;
      counter.value = 42;

      term::Term t = resource::make_term(&e, ptr);
      resource::release(ptr);

      return term::make_ok_tuple(&e, t).raw();
  }

  fn erl_nif::ErlNifTerm get_counter_value(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);

      term::Term? arg = macros::@require_arg(&e, argv, argc, 0);
      if (catch err = arg) {
          return safety::make_badarg_error(&e).raw();
      }

      // Use @get_resource to extract the typed resource
      void* ptr;
      if (erl_nif::enif_get_resource(e.raw(), arg.raw(), counter_resource_type, &ptr) == 0) {
          return safety::make_badarg_error(&e).raw();
      }
      Counter* counter = (Counter*)ptr;

      return term::make_ok_tuple(&e, term::make_int(&e, counter.value)).raw();
  }

  // =============================================================================
  // NIF on_load callback
  // =============================================================================

  fn CInt on_load(erl_nif::ErlNifEnv* env, void** priv, erl_nif::ErlNifTerm load_info) {
      env::Env e = env::wrap(env);

      // Register the counter resource type
      erl_nif::ErlNifResourceTypeInit init = {
          .dtor = null,
          .stop = null,
          .down = null,
          .members = 0,
          .dyncall = null
      };

      erl_nif::ErlNifResourceFlags tried;
      counter_resource_type = erl_nif::enif_init_resource_type(
          e.raw(),
          "Counter",
          &init,
          erl_nif::ErlNifResourceFlags.RT_CREATE,
          &tried
      );

      if (counter_resource_type == null) {
          return 1;
      }

      return 0;
  }

  // =============================================================================
  // NIF Entry
  // =============================================================================

  erl_nif::ErlNifFunc[10] nif_funcs = {
      { .name = "add_with_macro", .arity = 2, .fptr = &add_with_macro, .flags = 0 },
      { .name = "add_with_custom_error", .arity = 2, .fptr = &add_with_custom_error, .flags = 0 },
      { .name = "require_arg_int_test", .arity = 1, .fptr = &require_arg_int_test, .flags = 0 },
      { .name = "require_arg_long_test", .arity = 1, .fptr = &require_arg_long_test, .flags = 0 },
      { .name = "require_arg_double_test", .arity = 1, .fptr = &require_arg_double_test, .flags = 0 },
      { .name = "require_arg_uint_test", .arity = 1, .fptr = &require_arg_uint_test, .flags = 0 },
      { .name = "require_atom_macro", .arity = 1, .fptr = &require_atom_macro, .flags = 0 },
      { .name = "require_list_macro", .arity = 1, .fptr = &require_list_macro, .flags = 0 },
      { .name = "require_map_macro", .arity = 1, .fptr = &require_map_macro, .flags = 0 },
      { .name = "create_counter", .arity = 0, .fptr = &create_counter, .flags = 0 },
  };

  erl_nif::ErlNifEntry nif_entry;

  fn erl_nif::ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.MacrosNif",
          &nif_funcs,
          10,
          &on_load,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.MacrosNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.MacrosNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.MacrosNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "@nif_entry macro" do
    test "successful call returns result" do
      assert C3nif.IntegrationTest.MacrosNif.add_with_macro(10, 20) == 30
    end

    test "with invalid first argument returns error tuple" do
      assert C3nif.IntegrationTest.MacrosNif.add_with_macro("not an int", 20) == {:error, :error}
    end

    test "with invalid second argument returns error tuple" do
      assert C3nif.IntegrationTest.MacrosNif.add_with_macro(10, :atom) == {:error, :error}
    end

    test "with custom error reason returns custom error" do
      assert C3nif.IntegrationTest.MacrosNif.add_with_custom_error("bad", 10) ==
               {:error, :custom_error}
    end
  end

  describe "@require_arg_int macro" do
    test "with valid integer returns {:ok, value}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_int_test(42) == {:ok, 42}
    end

    test "with negative integer returns {:ok, value}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_int_test(-100) == {:ok, -100}
    end

    test "with non-integer returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_int_test("string") == {:error, :badarg}
    end

    test "with float returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_int_test(3.14) == {:error, :badarg}
    end
  end

  describe "@require_arg_long macro" do
    test "with valid integer returns {:ok, value}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_long_test(9_999_999_999) ==
               {:ok, 9_999_999_999}
    end

    test "with negative returns {:ok, value}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_long_test(-9_999_999_999) ==
               {:ok, -9_999_999_999}
    end

    test "with non-integer returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_long_test(:atom) == {:error, :badarg}
    end
  end

  describe "@require_arg_double macro" do
    test "with valid float returns {:ok, value}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_double_test(3.14159) == {:ok, 3.14159}
    end

    test "with integer returns {:error, :badarg}" do
      # Note: In Erlang NIFs, integers are not automatically converted to doubles
      assert C3nif.IntegrationTest.MacrosNif.require_arg_double_test(42) == {:error, :badarg}
    end

    test "with negative float returns {:ok, value}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_double_test(-2.718) == {:ok, -2.718}
    end

    test "with string returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_double_test("3.14") == {:error, :badarg}
    end
  end

  describe "@require_arg_uint macro" do
    test "with valid unsigned integer returns {:ok, value}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_uint_test(42) == {:ok, 42}
    end

    test "with zero returns {:ok, 0}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_uint_test(0) == {:ok, 0}
    end

    test "with negative returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_arg_uint_test(-1) == {:error, :badarg}
    end
  end

  describe "@require_type macro" do
    test "require_atom with atom returns :ok" do
      assert C3nif.IntegrationTest.MacrosNif.require_atom_macro(:hello) == :ok
    end

    test "require_atom with string returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_atom_macro("hello") == {:error, :badarg}
    end

    test "require_atom with integer returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_atom_macro(42) == {:error, :badarg}
    end

    test "require_list with list returns :ok" do
      assert C3nif.IntegrationTest.MacrosNif.require_list_macro([1, 2, 3]) == :ok
    end

    test "require_list with empty list returns :ok" do
      assert C3nif.IntegrationTest.MacrosNif.require_list_macro([]) == :ok
    end

    test "require_list with non-list returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_list_macro(:not_a_list) == {:error, :badarg}
    end

    test "require_map with map returns :ok" do
      assert C3nif.IntegrationTest.MacrosNif.require_map_macro(%{a: 1}) == :ok
    end

    test "require_map with empty map returns :ok" do
      assert C3nif.IntegrationTest.MacrosNif.require_map_macro(%{}) == :ok
    end

    test "require_map with non-map returns {:error, :badarg}" do
      assert C3nif.IntegrationTest.MacrosNif.require_map_macro([key: 1]) == {:error, :badarg}
    end
  end

  describe "resource with macros" do
    test "create_counter returns {:ok, resource}" do
      assert {:ok, resource} = C3nif.IntegrationTest.MacrosNif.create_counter()
      assert is_reference(resource)
    end
  end
end
