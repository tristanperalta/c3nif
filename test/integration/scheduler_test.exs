# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.SchedulerNif do
  @nif_path_base "libC3nif.IntegrationTest.SchedulerNif"

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

  # Thread type detection
  def get_thread_type, do: :erlang.nif_error(:nif_not_loaded)
  def is_dirty_scheduler, do: :erlang.nif_error(:nif_not_loaded)
  def is_normal_scheduler, do: :erlang.nif_error(:nif_not_loaded)

  # Process alive check
  def is_process_alive, do: :erlang.nif_error(:nif_not_loaded)

  # Timeslice consumption
  def consume_timeslice(_percent), do: :erlang.nif_error(:nif_not_loaded)

  # Dirty scheduler tests (static declaration)
  def dirty_cpu_work, do: :erlang.nif_error(:nif_not_loaded)
  def dirty_io_work, do: :erlang.nif_error(:nif_not_loaded)

  # Dynamic scheduling tests
  def dispatch_to_dirty_cpu, do: :erlang.nif_error(:nif_not_loaded)
  def dispatch_to_dirty_io, do: :erlang.nif_error(:nif_not_loaded)
  def dirty_then_normal, do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.SchedulerTest do
  use C3nif.Case, async: false

  alias C3nif.IntegrationTest.SchedulerNif

  @moduletag :integration

  @c3_code """
  module scheduler_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::scheduler;

  // =============================================================================
  // Thread Type Detection Tests
  // =============================================================================

  // NIF: get_thread_type() -> :undefined | :normal | :dirty_cpu | :dirty_io
  fn ErlNifTerm get_thread_type(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      ThreadType t = scheduler::current_thread_type();
      // C3 switch is exhaustive for enums - no fall-through, implicit break
      switch (t) {
          case ThreadType.UNDEFINED:
              return term::make_atom(&e, "undefined").raw();
          case ThreadType.NORMAL:
              return term::make_atom(&e, "normal").raw();
          case ThreadType.DIRTY_CPU:
              return term::make_atom(&e, "dirty_cpu").raw();
          case ThreadType.DIRTY_IO:
              return term::make_atom(&e, "dirty_io").raw();
      }
  }

  // NIF: is_dirty_scheduler() -> boolean
  fn ErlNifTerm is_dirty_scheduler(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      bool is_dirty = scheduler::is_dirty_scheduler();
      if (is_dirty) {
          return term::make_atom(&e, "true").raw();
      }
      return term::make_atom(&e, "false").raw();
  }

  // NIF: is_normal_scheduler() -> boolean
  fn ErlNifTerm is_normal_scheduler(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      bool is_normal = scheduler::is_normal_scheduler();
      if (is_normal) {
          return term::make_atom(&e, "true").raw();
      }
      return term::make_atom(&e, "false").raw();
  }

  // =============================================================================
  // Process Alive Check
  // =============================================================================

  // NIF: is_process_alive() -> boolean
  fn ErlNifTerm is_process_alive(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      bool alive = scheduler::is_process_alive(&e);
      if (alive) {
          return term::make_atom(&e, "true").raw();
      }
      return term::make_atom(&e, "false").raw();
  }

  // =============================================================================
  // Timeslice Consumption
  // =============================================================================

  // NIF: consume_timeslice(percent) -> :continue | :yield
  fn ErlNifTerm consume_timeslice(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      Term? arg = c3nif::get_arg(argv, argc, 0);
      if (catch err = arg) {
          return c3nif::make_badarg_error(&e).raw();
      }

      int? percent = c3nif::require_int(&e, arg);
      if (catch err = percent) {
          return c3nif::make_badarg_error(&e).raw();
      }

      bool should_yield = e.consume_timeslice(percent);
      if (should_yield) {
          return term::make_atom(&e, "yield").raw();
      }
      return term::make_atom(&e, "continue").raw();
  }

  // =============================================================================
  // Static Dirty Scheduler NIFs
  // =============================================================================

  // NIF: dirty_cpu_work() -> {:ok, :dirty_cpu}
  // Declared with ERL_NIF_DIRTY_JOB_CPU_BOUND flag
  fn ErlNifTerm dirty_cpu_work(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      // Verify we're on a dirty CPU scheduler
      ThreadType t = scheduler::current_thread_type();
      char* thread_name;
      // C3 switch assigns to variable - no fall-through
      switch (t) {
          case ThreadType.DIRTY_CPU: thread_name = "dirty_cpu";
          case ThreadType.DIRTY_IO: thread_name = "dirty_io";
          case ThreadType.NORMAL: thread_name = "normal";
          case ThreadType.UNDEFINED: thread_name = "undefined";
      }

      return term::make_ok_tuple(&e, term::make_atom(&e, thread_name)).raw();
  }

  // NIF: dirty_io_work() -> {:ok, :dirty_io}
  // Declared with ERL_NIF_DIRTY_JOB_IO_BOUND flag
  fn ErlNifTerm dirty_io_work(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);

      // Verify we're on a dirty IO scheduler
      ThreadType t = scheduler::current_thread_type();
      char* thread_name;
      switch (t) {
          case ThreadType.DIRTY_CPU: thread_name = "dirty_cpu";
          case ThreadType.DIRTY_IO: thread_name = "dirty_io";
          case ThreadType.NORMAL: thread_name = "normal";
          case ThreadType.UNDEFINED: thread_name = "undefined";
      }

      return term::make_ok_tuple(&e, term::make_atom(&e, thread_name)).raw();
  }

  // =============================================================================
  // Dynamic Scheduling Tests
  // =============================================================================

  // Helper: actual CPU work after scheduling
  fn ErlNifTerm do_cpu_work(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      ThreadType t = scheduler::current_thread_type();

      if (t == ThreadType.DIRTY_CPU) {
          return term::make_ok_tuple(&e, term::make_atom(&e, "dirty_cpu")).raw();
      }
      return term::make_error_atom(&e, "wrong_scheduler").raw();
  }

  // Helper: actual IO work after scheduling
  fn ErlNifTerm do_io_work(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      ThreadType t = scheduler::current_thread_type();

      if (t == ThreadType.DIRTY_IO) {
          return term::make_ok_tuple(&e, term::make_atom(&e, "dirty_io")).raw();
      }
      return term::make_error_atom(&e, "wrong_scheduler").raw();
  }

  // NIF: dispatch_to_dirty_cpu() -> {:ok, :dirty_cpu}
  fn ErlNifTerm dispatch_to_dirty_cpu(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      return scheduler::schedule_dirty_cpu(&e, "do_cpu_work", &do_cpu_work, 0, null).raw();
  }

  // NIF: dispatch_to_dirty_io() -> {:ok, :dirty_io}
  fn ErlNifTerm dispatch_to_dirty_io(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      return scheduler::schedule_dirty_io(&e, "do_io_work", &do_io_work, 0, null).raw();
  }

  // Helper: run on normal after dirty
  fn ErlNifTerm finish_on_normal(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      ThreadType t = scheduler::current_thread_type();

      if (t == ThreadType.NORMAL) {
          return term::make_ok_tuple(&e, term::make_atom(&e, "back_to_normal")).raw();
      }
      return term::make_error_atom(&e, "still_dirty").raw();
  }

  // Helper: work on dirty, then schedule back to normal
  fn ErlNifTerm dirty_work_then_normal(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      ThreadType t = scheduler::current_thread_type();

      if (t != ThreadType.DIRTY_CPU) {
          return term::make_error_atom(&e, "not_on_dirty").raw();
      }

      // Schedule back to normal scheduler
      return scheduler::schedule_normal(&e, "finish_on_normal", &finish_on_normal, 0, null).raw();
  }

  // NIF: dirty_then_normal() -> {:ok, :back_to_normal}
  fn ErlNifTerm dirty_then_normal(
      ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv
  ) {
      Env e = env::wrap(env_raw);
      // First schedule to dirty CPU
      return scheduler::schedule_dirty_cpu(&e, "dirty_work_then_normal", &dirty_work_then_normal, 0, null).raw();
  }

  // =============================================================================
  // NIF Entry
  // =============================================================================

  ErlNifFunc[10] nif_funcs = {
      { .name = "get_thread_type", .arity = 0, .fptr = &get_thread_type, .flags = 0 },
      { .name = "is_dirty_scheduler", .arity = 0, .fptr = &is_dirty_scheduler, .flags = 0 },
      { .name = "is_normal_scheduler", .arity = 0, .fptr = &is_normal_scheduler, .flags = 0 },
      { .name = "is_process_alive", .arity = 0, .fptr = &is_process_alive, .flags = 0 },
      { .name = "consume_timeslice", .arity = 1, .fptr = &consume_timeslice, .flags = 0 },
      { .name = "dirty_cpu_work", .arity = 0, .fptr = &dirty_cpu_work, .flags = erl_nif::ERL_NIF_DIRTY_JOB_CPU_BOUND },
      { .name = "dirty_io_work", .arity = 0, .fptr = &dirty_io_work, .flags = erl_nif::ERL_NIF_DIRTY_JOB_IO_BOUND },
      { .name = "dispatch_to_dirty_cpu", .arity = 0, .fptr = &dispatch_to_dirty_cpu, .flags = 0 },
      { .name = "dispatch_to_dirty_io", .arity = 0, .fptr = &dispatch_to_dirty_io, .flags = 0 },
      { .name = "dirty_then_normal", .arity = 0, .fptr = &dirty_then_normal, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.SchedulerNif",
          &nif_funcs,
          10,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.SchedulerNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.SchedulerNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case SchedulerNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  describe "thread type detection" do
    test "get_thread_type returns :normal on normal scheduler" do
      assert SchedulerNif.get_thread_type() == :normal
    end

    test "is_normal_scheduler returns true on normal scheduler" do
      assert SchedulerNif.is_normal_scheduler() == true
    end

    test "is_dirty_scheduler returns false on normal scheduler" do
      assert SchedulerNif.is_dirty_scheduler() == false
    end
  end

  describe "process alive check" do
    test "is_process_alive returns true for running process" do
      assert SchedulerNif.is_process_alive() == true
    end
  end

  describe "timeslice consumption" do
    test "consume_timeslice with low percent returns :continue" do
      # Consuming 1% of timeslice should not exhaust it
      assert SchedulerNif.consume_timeslice(1) == :continue
    end

    test "consume_timeslice with high percent eventually returns :yield" do
      # Keep consuming until we should yield
      # Note: This might not always work in a single call, depends on scheduler state
      result =
        Enum.reduce_while(1..100, :continue, fn _, _acc ->
          case SchedulerNif.consume_timeslice(100) do
            :yield -> {:halt, :yield}
            :continue -> {:cont, :continue}
          end
        end)

      # We should eventually get a yield
      assert result == :yield
    end

    test "consume_timeslice with invalid arg returns error" do
      assert SchedulerNif.consume_timeslice(:not_int) ==
               {:error, :badarg}
    end
  end

  describe "static dirty scheduler declaration" do
    test "dirty_cpu_work runs on dirty CPU scheduler" do
      assert SchedulerNif.dirty_cpu_work() == {:ok, :dirty_cpu}
    end

    test "dirty_io_work runs on dirty IO scheduler" do
      assert SchedulerNif.dirty_io_work() == {:ok, :dirty_io}
    end
  end

  describe "dynamic scheduling" do
    test "dispatch_to_dirty_cpu schedules to CPU scheduler" do
      assert SchedulerNif.dispatch_to_dirty_cpu() == {:ok, :dirty_cpu}
    end

    test "dispatch_to_dirty_io schedules to IO scheduler" do
      assert SchedulerNif.dispatch_to_dirty_io() == {:ok, :dirty_io}
    end

    test "dirty_then_normal transitions dirty -> normal" do
      assert SchedulerNif.dirty_then_normal() == {:ok, :back_to_normal}
    end
  end
end
