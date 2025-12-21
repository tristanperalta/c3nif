defmodule Mix.Tasks.Compile.C3nif do
  @moduledoc """
  Compiles C3 NIF modules.

  This task is automatically run before compilation and tests.
  It performs two operations:

  1. Compiles the c3nif.c3l runtime library (when in development)
  2. Compiles all NIF modules that use C3nif

  ## Incremental Compilation

  The task tracks source file modifications and only recompiles when:
  - The C3 source code has changed
  - Any external source files (`:c3_sources`) have changed
  - The output library doesn't exist
  """

  use Mix.Task

  alias C3nif
  alias C3nif.Compiler

  @shortdoc "Compiles C3 NIF modules"

  @impl Mix.Task
  def run(_args) do
    # First, compile the c3nif.c3l library if we're in development
    c3nif_dir = Path.join(File.cwd!(), "c3nif.c3l")

    if File.exists?(c3nif_dir) do
      compile_c3nif_library(c3nif_dir)
    end

    # Then compile all registered NIF modules
    compile_nif_modules()
  end

  # ===========================================================================
  # NIF Module Compilation
  # ===========================================================================

  defp compile_nif_modules do
    manifest_file = Compiler.manifest_path()

    if File.exists?(manifest_file) do
      manifest =
        manifest_file
        |> File.read!()
        |> :erlang.binary_to_term()

      Enum.each(manifest, fn {module, entry} ->
        compile_nif_module(module, entry)
      end)
    end

    :ok
  end

  defp compile_nif_module(module, entry) do
    %{
      otp_app: otp_app,
      c3_code: c3_code,
      c3_sources: c3_sources,
      source_file: source_file
    } = entry

    nif_name = "lib#{module}#{C3nif.nif_extension()}"
    priv_dir = Application.app_dir(otp_app, "priv")
    output_path = Path.join(priv_dir, nif_name)

    # Collect all source files for mtime comparison
    all_sources = collect_source_files(source_file, c3_sources)

    if nif_needs_recompile?(output_path, all_sources) do
      Mix.shell().info("Compiling NIF #{module}...")

      case Compiler.compile(
             module: module,
             otp_app: otp_app,
             c3_code: c3_code,
             c3_sources: c3_sources
           ) do
        {:ok, lib_path} ->
          # Copy to priv directory
          File.mkdir_p!(priv_dir)
          File.cp!(lib_path, output_path)
          :ok

        {:error, {:compile_failed, exit_code, output}} ->
          Mix.raise("""
          Failed to compile NIF #{module} (exit code #{exit_code}):

          #{output}
          """)
      end
    end
  end

  defp collect_source_files(source_file, c3_sources) do
    # Start with the main module source file
    sources =
      if source_file && source_file != "nofile" && File.exists?(source_file) do
        [source_file]
      else
        []
      end

    # Add expanded external sources
    external_sources =
      c3_sources
      |> Enum.flat_map(fn pattern ->
        abs_pattern = Path.expand(pattern, File.cwd!())

        cond do
          String.contains?(pattern, "*") -> Path.wildcard(abs_pattern)
          File.exists?(abs_pattern) -> [abs_pattern]
          true -> []
        end
      end)

    sources ++ external_sources
  end

  defp nif_needs_recompile?(output_path, source_files) do
    if File.exists?(output_path) do
      output_mtime = File.stat!(output_path).mtime

      Enum.any?(source_files, fn source ->
        File.exists?(source) && File.stat!(source).mtime > output_mtime
      end)
    else
      true
    end
  end

  # ===========================================================================
  # c3nif.c3l Library Compilation
  # ===========================================================================

  defp compile_c3nif_library(c3nif_dir) do
    output_file = Path.join(c3nif_dir, "c3nif.a")
    source_files = Path.wildcard(Path.join(c3nif_dir, "*.c3"))

    if library_needs_recompile?(output_file, source_files) do
      do_compile_library(c3nif_dir)
    else
      :ok
    end
  end

  defp library_needs_recompile?(output_file, source_files) do
    if File.exists?(output_file) do
      output_mtime = File.stat!(output_file).mtime

      Enum.any?(source_files, fn source ->
        File.stat!(source).mtime > output_mtime
      end)
    else
      true
    end
  end

  defp do_compile_library(c3nif_dir) do
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
