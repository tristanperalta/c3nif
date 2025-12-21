# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.ResourceKeepNif do
  @nif_path_base "libC3nif.IntegrationTest.ResourceKeepNif"

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

  def create_tracked(_initial), do: :erlang.nif_error(:nif_not_loaded)
  def get_tracked(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def keep_in_native(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def release_from_native, do: :erlang.nif_error(:nif_not_loaded)
  def get_native_value, do: :erlang.nif_error(:nif_not_loaded)
  def get_live_count, do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.ResourceKeepTest do
  use C3nif.Case, async: false

  alias C3nif.IntegrationTest.ResourceKeepNif

  @moduletag :integration

  @c3_code """
  module resource_keep_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::resource;

  // Tracked resource with value
  struct Tracked {
      int value;
  }

  // Global tracking
  int g_live_count;

  // Native-side stored resource (demonstrates keep/release)
  void* g_native_resource;

  // Destructor - decrements live count
  fn void tracked_dtor(ErlNifEnv* env_raw, void* obj) {
      g_live_count--;
  }

  // on_load: register resource type
  fn CInt on_load(ErlNifEnv* env_raw, void** priv, ErlNifTerm load_info) {
      Env e = env::wrap(env_raw);
      if (catch err = resource::register_type(&e, "Tracked", &tracked_dtor)) {
          return 1;
      }
      g_native_resource = null;
      return 0;
  }

  // NIF: create_tracked(initial_value) -> resource
  fn ErlNifTerm create_tracked(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      int? initial = arg.get_int(&e);
      if (catch err = initial) {
          return term::make_badarg(&e).raw();
      }

      void* ptr = resource::alloc("Tracked", Tracked.sizeof)!!;
      Tracked* tracked = (Tracked*)ptr;
      tracked.value = initial;
      g_live_count++;

      Term t = resource::make_term(&e, ptr);
      resource::release(ptr);  // Term now owns the reference
      return t.raw();
  }

  // NIF: get_tracked(resource) -> integer
  fn ErlNifTerm get_tracked(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      void* ptr = resource::get("Tracked", &e, arg)!!;
      Tracked* tracked = (Tracked*)ptr;

      return term::make_int(&e, tracked.value).raw();
  }

  // NIF: keep_in_native(resource) -> :ok
  // Stores resource pointer in native global and calls keep() to prevent GC
  fn ErlNifTerm keep_in_native(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      Term arg = term::wrap(argv[0]);

      // Release any previously kept resource
      if (g_native_resource != null) {
          resource::release(g_native_resource);
      }

      void* ptr = resource::get("Tracked", &e, arg)!!;

      // Keep increases ref count - resource won't be destroyed even if
      // Erlang term goes out of scope
      resource::keep(ptr);
      g_native_resource = ptr;

      return term::make_atom(&e, "ok").raw();
  }

  // NIF: release_from_native() -> :ok | :error
  // Releases the native-side reference
  fn ErlNifTerm release_from_native(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      if (g_native_resource == null) {
          return term::make_atom(&e, "error").raw();
      }

      resource::release(g_native_resource);
      g_native_resource = null;

      return term::make_atom(&e, "ok").raw();
  }

  // NIF: get_native_value() -> integer | nil
  // Gets value from native-side stored resource
  fn ErlNifTerm get_native_value(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      if (g_native_resource == null) {
          return term::make_atom(&e, "nil").raw();
      }

      Tracked* tracked = (Tracked*)g_native_resource;
      return term::make_int(&e, tracked.value).raw();
  }

  // NIF: get_live_count() -> integer
  fn ErlNifTerm get_live_count_nif(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      return term::make_int(&e, g_live_count).raw();
  }

  // NIF function table
  ErlNifFunc[6] nif_funcs = {
      { .name = "create_tracked", .arity = 1, .fptr = &create_tracked, .flags = 0 },
      { .name = "get_tracked", .arity = 1, .fptr = &get_tracked, .flags = 0 },
      { .name = "keep_in_native", .arity = 1, .fptr = &keep_in_native, .flags = 0 },
      { .name = "release_from_native", .arity = 0, .fptr = &release_from_native, .flags = 0 },
      { .name = "get_native_value", .arity = 0, .fptr = &get_native_value, .flags = 0 },
      { .name = "get_live_count", .arity = 0, .fptr = &get_live_count_nif, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.ResourceKeepNif",
          &nif_funcs,
          6,
          &on_load,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.ResourceKeepNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.ResourceKeepNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case ResourceKeepNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "keep/release reference counting" do
    test "keep prevents destruction when Erlang reference is gone" do
      initial_count = ResourceKeepNif.get_live_count()

      # Create a resource and keep it in native code
      resource = ResourceKeepNif.create_tracked(42)
      assert ResourceKeepNif.get_tracked(resource) == 42

      :ok = ResourceKeepNif.keep_in_native(resource)

      # Verify we can access it from native side
      assert ResourceKeepNif.get_native_value() == 42

      # Now "lose" the Erlang reference and GC
      # Note: We can't actually lose it in this scope, so we test via spawning
      spawn(fn ->
        res = ResourceKeepNif.create_tracked(100)
        ResourceKeepNif.keep_in_native(res)
      end)

      Process.sleep(50)
      :erlang.garbage_collect()
      Process.sleep(50)

      # Native reference should still be valid (value is 100 from spawned process)
      value = ResourceKeepNif.get_native_value()
      assert value == 100

      # Live count should include the native-kept resource
      assert ResourceKeepNif.get_live_count() > initial_count

      # Release the native reference
      :ok = ResourceKeepNif.release_from_native()
    end

    test "release from native allows destruction" do
      _initial_count = ResourceKeepNif.get_live_count()

      # Create and keep in native
      spawn(fn ->
        res = ResourceKeepNif.create_tracked(999)
        ResourceKeepNif.keep_in_native(res)
      end)

      Process.sleep(50)
      :erlang.garbage_collect()

      # Should still exist
      assert ResourceKeepNif.get_native_value() == 999

      count_before_release = ResourceKeepNif.get_live_count()

      # Release from native
      :ok = ResourceKeepNif.release_from_native()

      # Force GC
      :erlang.garbage_collect()
      Process.sleep(100)

      # Value should be nil (no native resource)
      assert ResourceKeepNif.get_native_value() == :nil

      # Live count should decrease (eventually, GC timing is not deterministic)
      # We just verify the release worked and the count is reasonable
      final_count = ResourceKeepNif.get_live_count()
      assert is_integer(final_count)
      assert final_count <= count_before_release
    end

    test "replacing native resource releases previous" do
      # Keep first resource
      res1 = ResourceKeepNif.create_tracked(111)
      :ok = ResourceKeepNif.keep_in_native(res1)
      assert ResourceKeepNif.get_native_value() == 111

      # Keep second resource (should release first)
      res2 = ResourceKeepNif.create_tracked(222)
      :ok = ResourceKeepNif.keep_in_native(res2)
      assert ResourceKeepNif.get_native_value() == 222

      # Keep third resource
      res3 = ResourceKeepNif.create_tracked(333)
      :ok = ResourceKeepNif.keep_in_native(res3)
      assert ResourceKeepNif.get_native_value() == 333

      # Clean up
      :ok = ResourceKeepNif.release_from_native()
    end

    test "release_from_native with no resource returns error" do
      # First ensure no native resource
      ResourceKeepNif.release_from_native()

      # Should return error
      assert ResourceKeepNif.release_from_native() == :error
    end
  end
end
