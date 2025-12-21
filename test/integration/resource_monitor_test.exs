# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.ResourceMonitorNif do
  @nif_path_base "libC3nif.IntegrationTest.ResourceMonitorNif"

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

  def create_monitored_resource(_owner_pid, _notify_pid), do: :erlang.nif_error(:nif_not_loaded)
  def get_down_count, do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.ResourceMonitorTest do
  use C3nif.Case, async: false

  alias C3nif.IntegrationTest.ResourceMonitorNif

  @moduletag :integration

  @c3_code """
  module resource_monitor_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::resource;

  // Resource that monitors a process and notifies another when it dies
  struct Monitor {
      ErlNifPid notify_pid;   // PID to notify on process death
      ErlNifPid monitored_pid; // PID being monitored
      ErlNifMonitor monitor;   // Monitor handle
  }

  // Global counter for down callback invocations
  int g_down_count;

  // Destructor - just cleanup, no special logic needed
  fn void monitor_dtor(ErlNifEnv* env_raw, void* obj) {
      // Resource cleanup happens automatically
  }

  // Down callback - called when monitored process dies
  fn void monitor_down(
      ErlNifEnv* env_raw,
      void* obj,
      ErlNifPid* dead_pid,
      ErlNifMonitor* monitor
  ) {
      Monitor* m = (Monitor*)obj;
      g_down_count++;

      // Send notification message to notify_pid
      ErlNifEnv* msg_env = erl_nif::enif_alloc_env();
      if (msg_env == null) {
          return;
      }

      // Create tuple {:process_down, dead_pid}
      ErlNifTerm atom = erl_nif::enif_make_atom(msg_env, "process_down");
      ErlNifTerm pid_term = erl_nif::make_pid(msg_env, dead_pid);
      ErlNifTerm[2] tuple_elems = { atom, pid_term };
      ErlNifTerm msg = erl_nif::enif_make_tuple_from_array(msg_env, &tuple_elems, 2);

      // Send the message
      erl_nif::enif_send(null, &m.notify_pid, msg_env, msg);

      erl_nif::enif_free_env(msg_env);
  }

  // on_load: register resource type with down callback
  fn CInt on_load(ErlNifEnv* env_raw, void** priv, ErlNifTerm load_info) {
      Env e = env::wrap(env_raw);

      // Use register_type_full to enable down callback
      // .members >= 3 is required for down callback support
      erl_nif::ErlNifResourceTypeInit init = {
          .dtor = &monitor_dtor,
          .stop = null,
          .down = &monitor_down,
          .members = 3,  // Critical: enables down callback
          .dyncall = null
      };

      if (catch err = resource::register_type_full(&e, "Monitor", &init)) {
          return 1;
      }
      return 0;
  }

  // NIF: create_monitored_resource(owner_pid, notify_pid) -> resource
  // Creates a resource that monitors owner_pid and notifies notify_pid when owner dies
  fn ErlNifTerm create_monitored_resource(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      // Get owner_pid (the process to monitor)
      ErlNifPid owner_pid;
      if (erl_nif::enif_get_local_pid(env_raw, argv[0], &owner_pid) == 0) {
          return term::make_badarg(&e).raw();
      }

      // Get notify_pid (the process to notify on death)
      ErlNifPid notify_pid;
      if (erl_nif::enif_get_local_pid(env_raw, argv[1], &notify_pid) == 0) {
          return term::make_badarg(&e).raw();
      }

      // Allocate the resource
      void* ptr = resource::alloc("Monitor", Monitor.sizeof)!!;
      Monitor* m = (Monitor*)ptr;
      m.notify_pid = notify_pid;
      m.monitored_pid = owner_pid;

      // Start monitoring the owner process
      if (!resource::monitor_process(&e, ptr, &owner_pid, &m.monitor)) {
          // Monitoring failed - process might already be dead
          resource::release(ptr);
          return term::make_badarg(&e).raw();
      }

      Term t = resource::make_term(&e, ptr);
      resource::release(ptr);  // Term now owns the reference
      return t.raw();
  }

  // NIF: get_down_count() -> integer
  fn ErlNifTerm get_down_count_nif(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      return term::make_int(&e, g_down_count).raw();
  }

  // NIF function table
  ErlNifFunc[2] nif_funcs = {
      { .name = "create_monitored_resource", .arity = 2, .fptr = &create_monitored_resource, .flags = 0 },
      { .name = "get_down_count", .arity = 0, .fptr = &get_down_count_nif, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.ResourceMonitorNif",
          &nif_funcs,
          2,
          &on_load,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.ResourceMonitorNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.ResourceMonitorNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case ResourceMonitorNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "process monitoring" do
    test "down callback fires when monitored process dies" do
      notify_pid = self()

      # Create a process to monitor
      monitored =
        spawn(fn ->
          receive do
            :die -> :ok
          end
        end)

      # Create resource that monitors the process
      _resource =
        ResourceMonitorNif.create_monitored_resource(
          monitored,
          notify_pid
        )

      # Kill the monitored process
      send(monitored, :die)

      # Should receive notification from down callback
      assert_receive {:process_down, ^monitored}, 1000
    end

    test "down callback count increments" do
      initial = ResourceMonitorNif.get_down_count()

      # Create and kill monitored processes
      for _ <- 1..3 do
        monitored =
          spawn(fn ->
            receive do
              :die -> :ok
            end
          end)

        _resource =
          ResourceMonitorNif.create_monitored_resource(
            monitored,
            self()
          )

        send(monitored, :die)
        assert_receive {:process_down, _}, 1000
      end

      final = ResourceMonitorNif.get_down_count()
      assert final >= initial + 3
    end

    test "down callback does not fire if process stays alive" do
      notify_pid = self()

      # Create a long-living process
      monitored =
        spawn(fn ->
          receive do
            :exit -> :ok
          after
            5000 -> :timeout
          end
        end)

      # Create resource that monitors the process
      _resource =
        ResourceMonitorNif.create_monitored_resource(
          monitored,
          notify_pid
        )

      # Should NOT receive notification since process is alive
      refute_receive {:process_down, _}, 200

      # Clean up
      send(monitored, :exit)
      assert_receive {:process_down, ^monitored}, 1000
    end

    test "multiple monitors can track different processes" do
      notify_pid = self()

      # Create multiple processes
      pids =
        for i <- 1..3 do
          spawn(fn ->
            receive do
              {:die, ^i} -> :ok
            end
          end)
        end

      # Monitor each process
      for pid <- pids do
        _resource =
          ResourceMonitorNif.create_monitored_resource(
            pid,
            notify_pid
          )
      end

      # Kill processes in reverse order
      for {pid, i} <- Enum.with_index(Enum.reverse(pids), 1) do
        send(pid, {:die, 4 - i})
        assert_receive {:process_down, ^pid}, 1000
      end
    end
  end
end
