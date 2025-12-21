# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.ResourceCleanupNif do
  @nif_path_base "libC3nif.IntegrationTest.ResourceCleanupNif"

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

  def create_notifier(_pid), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.ResourceCleanupTest do
  use C3nif.Case, async: false

  alias C3nif.IntegrationTest.ResourceCleanupNif

  @moduletag :integration

  @c3_code """
  module resource_cleanup_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::resource;

  // Resource that holds a PID and sends message on destruction
  struct Notifier {
      ErlNifPid pid;
  }

  // Destructor callback - sends :cleaned message to stored PID
  fn void notifier_dtor(ErlNifEnv* env_raw, void* obj) {
      Notifier* notifier = (Notifier*)obj;

      // Create a new environment for sending (destructor env is special)
      ErlNifEnv* msg_env = erl_nif::enif_alloc_env();
      if (msg_env == null) {
          return;
      }

      // Create the :cleaned atom
      ErlNifTerm atom = erl_nif::enif_make_atom(msg_env, "cleaned");

      // Send the message
      erl_nif::enif_send(null, &notifier.pid, msg_env, atom);

      // Free the message environment
      erl_nif::enif_free_env(msg_env);
  }

  // on_load: register resource type
  fn CInt on_load(ErlNifEnv* env_raw, void** priv, ErlNifTerm load_info) {
      Env e = env::wrap(env_raw);
      if (catch err = resource::register_type(&e, "Notifier", &notifier_dtor)) {
          return 1;
      }
      return 0;
  }

  // NIF: create_notifier(pid) -> resource
  fn ErlNifTerm create_notifier(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      // Get the PID from argument
      ErlNifPid pid;
      if (erl_nif::enif_get_local_pid(env_raw, argv[0], &pid) == 0) {
          return term::make_badarg(&e).raw();
      }

      void* ptr = resource::alloc("Notifier", Notifier.sizeof)!!;
      Notifier* notifier = (Notifier*)ptr;
      notifier.pid = pid;

      Term t = resource::make_term(&e, ptr);
      resource::release(ptr);  // Term now owns the reference
      return t.raw();
  }

  // NIF function table
  ErlNifFunc[1] nif_funcs = {
      { .name = "create_notifier", .arity = 1, .fptr = &create_notifier, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.ResourceCleanupNif",
          &nif_funcs,
          1,
          &on_load,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.ResourceCleanupNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.ResourceCleanupNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case ResourceCleanupNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "destructor message passing (Zigler pattern)" do
    test "destructor sends message when process exits" do
      test_pid = self()

      # Spawn a process that creates a resource and immediately exits
      spawn(fn ->
        _resource = ResourceCleanupNif.create_notifier(test_pid)
        # Process exits, resource goes out of scope
      end)

      # Should receive :cleaned when the resource is garbage collected
      assert_receive :cleaned, 1000
    end

    test "destructor sends message after explicit GC" do
      test_pid = self()

      # Create resource in a spawned process
      child =
        spawn(fn ->
          _resource = ResourceCleanupNif.create_notifier(test_pid)

          receive do
            :exit -> :ok
          end
        end)

      # Resource exists, no message yet
      refute_receive :cleaned, 100

      # Tell the process to exit
      send(child, :exit)

      # Wait a bit for process to exit
      Process.sleep(50)

      # Force GC
      :erlang.garbage_collect()
      Process.sleep(50)

      # Should receive :cleaned
      assert_receive :cleaned, 1000
    end

    test "multiple resources each send cleanup message" do
      test_pid = self()

      # Spawn multiple processes, each creating a resource
      for _ <- 1..5 do
        spawn(fn ->
          _resource = ResourceCleanupNif.create_notifier(test_pid)
        end)
      end

      # Should receive 5 :cleaned messages
      for _ <- 1..5 do
        assert_receive :cleaned, 1000
      end

      # No more messages
      refute_receive :cleaned, 100
    end

    test "resource held by live process does not trigger cleanup" do
      test_pid = self()

      # Create a process that holds the resource alive
      holder =
        spawn(fn ->
          resource = ResourceCleanupNif.create_notifier(test_pid)

          receive do
            :release ->
              # Let resource go out of scope
              _ = resource
              :ok

            :keep_alive ->
              # Keep holding the resource
              keep_alive(resource)
          end
        end)

      # Wait and check - no cleanup should happen
      Process.sleep(100)
      :erlang.garbage_collect()
      Process.sleep(100)

      refute_receive :cleaned, 200

      # Now tell it to release
      send(holder, :release)

      # Should eventually get cleaned
      assert_receive :cleaned, 1000
    end
  end

  # Helper to prevent resource from being GC'd
  defp keep_alive(resource) do
    receive do
      :release ->
        _ = resource
        :ok

      :ping ->
        keep_alive(resource)
    end
  end
end
