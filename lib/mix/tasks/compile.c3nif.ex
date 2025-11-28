defmodule Mix.Tasks.Compile.C3nif do
  @moduledoc """
  Compiles the c3nif.c3l C3 runtime library.

  This task is automatically run before compilation and tests.
  It checks if any .c3 source files have changed since the last build
  and only recompiles when necessary.
  """

  use Mix.Task

  @shortdoc "Compiles the c3nif.c3l C3 library"

  @impl Mix.Task
  def run(_args) do
    c3nif_dir = Path.join(File.cwd!(), "c3nif.c3l")

    if File.exists?(c3nif_dir) do
      compile_c3nif(c3nif_dir)
    else
      # Not in the c3nif project directory, skip
      :ok
    end
  end

  defp compile_c3nif(c3nif_dir) do
    output_file = Path.join(c3nif_dir, "c3nif.a")
    source_files = Path.wildcard(Path.join(c3nif_dir, "*.c3"))

    if needs_recompile?(output_file, source_files) do
      do_compile(c3nif_dir)
    else
      :ok
    end
  end

  defp needs_recompile?(output_file, source_files) do
    if File.exists?(output_file) do
      output_mtime = File.stat!(output_file).mtime

      Enum.any?(source_files, fn source ->
        File.stat!(source).mtime > output_mtime
      end)
    else
      true
    end
  end

  defp do_compile(c3nif_dir) do
    case System.find_executable("c3c") do
      nil ->
        Mix.raise("c3c compiler not found. Please install C3: https://c3-lang.org")

      _c3c_path ->
        Mix.shell().info("Compiling c3nif.c3l...")

        case System.cmd("c3c", ["build"], cd: c3nif_dir, stderr_to_stdout: true) do
          {_output, 0} ->
            :ok

          {output, exit_code} ->
            Mix.raise("""
            Failed to compile c3nif.c3l (exit code #{exit_code}):

            #{output}
            """)
        end
    end
  end
end
