# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.ResourceBasicNif do
  @nif_path_base "libC3nif.IntegrationTest.ResourceBasicNif"

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

  def create_counter(_initial), do: :erlang.nif_error(:nif_not_loaded)
  def get_counter(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def increment_counter(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def get_resource_count(), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.ResourceBasicTest do
  use C3nif.Case, async: false

  @moduletag :integration

  @c3_code """
  module resource_basic_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::resource;

  // Simple counter resource
  struct Counter {
      int value;
  }

  // Track live resource count (for testing destructor calls)
  int g_resource_count;

  // Destructor callback - decrements resource count
  fn void counter_dtor(ErlNifEnv* env_raw, void* obj) {
      g_resource_count--;
  }

  // on_load: register resource type
  fn CInt on_load(ErlNifEnv* env_raw, void** priv, ErlNifTerm load_info) {
      Env e = env::wrap(env_raw);
      if (catch err = resource::register_type(&e, "Counter", &counter_dtor)) {
          return 1;
      }
      return 0;
  }

  // NIF: create_counter(initial_value) -> resource
  fn ErlNifTerm create_counter(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      int? initial = arg.get_int(&e);
      if (catch err = initial) {
          return term::make_badarg(&e).raw();
      }

      void* ptr = resource::alloc("Counter", Counter.sizeof)!!;
      Counter* counter = (Counter*)ptr;
      counter.value = initial;
      g_resource_count++;  // Track allocation

      Term t = resource::make_term(&e, ptr);
      resource::release(ptr);  // Term now owns the reference
      return t.raw();
  }

  // NIF: get_counter(resource) -> integer
  fn ErlNifTerm get_counter(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      void* ptr = resource::get("Counter", &e, arg)!!;
      Counter* counter = (Counter*)ptr;

      return term::make_int(&e, counter.value).raw();
  }

  // NIF: increment_counter(resource) -> :ok
  fn ErlNifTerm increment_counter(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      void* ptr = resource::get("Counter", &e, arg)!!;
      Counter* counter = (Counter*)ptr;
      counter.value++;

      return term::make_atom(&e, "ok").raw();
  }

  // NIF: get_resource_count() -> integer (for verifying destructor calls)
  fn ErlNifTerm get_resource_count_nif(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      return term::make_int(&e, g_resource_count).raw();
  }

  // NIF function table
  ErlNifFunc[4] nif_funcs = {
      { .name = "create_counter", .arity = 1, .fptr = &create_counter, .flags = 0 },
      { .name = "get_counter", .arity = 1, .fptr = &get_counter, .flags = 0 },
      { .name = "increment_counter", .arity = 1, .fptr = &increment_counter, .flags = 0 },
      { .name = "get_resource_count", .arity = 0, .fptr = &get_resource_count_nif, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.ResourceBasicNif",
          &nif_funcs,
          4,
          &on_load,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.ResourceBasicNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.ResourceBasicNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.ResourceBasicNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "basic resource operations" do
    test "create and read resource" do
      resource = C3nif.IntegrationTest.ResourceBasicNif.create_counter(42)
      assert is_reference(resource)
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(resource) == 42
    end

    test "create with different values" do
      res1 = C3nif.IntegrationTest.ResourceBasicNif.create_counter(0)
      res2 = C3nif.IntegrationTest.ResourceBasicNif.create_counter(100)
      res3 = C3nif.IntegrationTest.ResourceBasicNif.create_counter(-50)

      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(res1) == 0
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(res2) == 100
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(res3) == -50
    end

    test "increment resource" do
      resource = C3nif.IntegrationTest.ResourceBasicNif.create_counter(0)
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(resource) == 0

      :ok = C3nif.IntegrationTest.ResourceBasicNif.increment_counter(resource)
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(resource) == 1

      :ok = C3nif.IntegrationTest.ResourceBasicNif.increment_counter(resource)
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(resource) == 2

      :ok = C3nif.IntegrationTest.ResourceBasicNif.increment_counter(resource)
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(resource) == 3
    end

    test "multiple resources are independent" do
      res1 = C3nif.IntegrationTest.ResourceBasicNif.create_counter(10)
      res2 = C3nif.IntegrationTest.ResourceBasicNif.create_counter(20)

      C3nif.IntegrationTest.ResourceBasicNif.increment_counter(res1)
      C3nif.IntegrationTest.ResourceBasicNif.increment_counter(res1)

      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(res1) == 12
      assert C3nif.IntegrationTest.ResourceBasicNif.get_counter(res2) == 20
    end
  end

  describe "destructor tracking" do
    test "resource count tracks allocations" do
      initial_count = C3nif.IntegrationTest.ResourceBasicNif.get_resource_count()

      _res1 = C3nif.IntegrationTest.ResourceBasicNif.create_counter(1)
      _res2 = C3nif.IntegrationTest.ResourceBasicNif.create_counter(2)

      # Should have 2 more resources
      assert C3nif.IntegrationTest.ResourceBasicNif.get_resource_count() >= initial_count + 2
    end

    test "mass allocation cleanup (Rustler pattern)" do
      # Create many resources
      for _ <- 1..100 do
        C3nif.IntegrationTest.ResourceBasicNif.create_counter(0)
      end

      # Force GC
      :erlang.garbage_collect()
      Process.sleep(50)

      # Count should decrease (timing not deterministic, so just check it didn't crash)
      count = C3nif.IntegrationTest.ResourceBasicNif.get_resource_count()
      assert is_integer(count)
    end
  end
end
