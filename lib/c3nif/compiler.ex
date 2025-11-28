defmodule C3nif.Compiler do
  @moduledoc """
  Compiler module for C3 NIFs.

  This module handles the compilation of C3 code and generation of Elixir bindings
  during the `@before_compile` phase.
  """

  require Logger

  @doc false
  defmacro __before_compile__(%{module: module, file: file}) do
    opts = Module.get_attribute(module, :c3nif_opts)
    otp_app = Keyword.fetch!(opts, :otp_app)

    # Get the accumulated C3 code
    c3_code =
      module
      |> Module.get_attribute(:c3_code_parts)
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    # Store the code for later retrieval
    Module.put_attribute(module, :c3_code, c3_code)

    # Determine where to put generated files
    code_dir =
      case file do
        "nofile" -> File.cwd!()
        _ -> Path.dirname(file)
      end

    # Generate module-specific C3 file
    c3_file_path = Path.join(code_dir, ".#{module}.c3")
    nif_name = nif_name(module)
    priv_dir = Application.app_dir(otp_app, "priv")

    # Build paths
    nif_path = Path.join(priv_dir, nif_name)

    quote do
      @c3_file_path unquote(c3_file_path)
      @nif_path unquote(nif_path)
      @nif_name unquote(nif_name)
      @otp_app unquote(otp_app)

      def __load_nifs__ do
        nif_path =
          @otp_app
          |> Application.app_dir("priv")
          |> Path.join(@nif_name)
          |> String.to_charlist()

        case :erlang.load_nif(nif_path, 0) do
          :ok ->
            :ok

          {:error, {:load_failed, reason}} ->
            Logger.warning("Failed to load NIF #{@nif_name}: #{inspect(reason)}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to load NIF #{@nif_name}: #{inspect(reason)}")
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Compiles C3 source code into a NIF shared library.

  ## Options

  - `:module` - The Elixir module name
  - `:otp_app` - The OTP application
  - `:c3_code` - The C3 source code
  - `:output_dir` - Directory for the compiled library
  """
  def compile(opts) do
    module = Keyword.fetch!(opts, :module)
    otp_app = Keyword.fetch!(opts, :otp_app)
    c3_code = Keyword.fetch!(opts, :c3_code)
    output_dir = Keyword.get(opts, :output_dir, staging_dir(module))

    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    # Write C3 source file
    c3_file = Path.join(output_dir, "#{module}.c3")
    File.write!(c3_file, c3_code)

    # Generate project.json for c3c
    project_json = generate_project_json(module, otp_app)
    project_file = Path.join(output_dir, "project.json")
    File.write!(project_file, JSON.encode!(project_json))

    # Link the c3nif library
    c3nif_src = c3nif_src_path()
    lib_dir = Path.join(output_dir, "lib")
    File.mkdir_p!(lib_dir)

    # Create symlink to c3nif.c3l library
    c3nif_lib_path = Path.join(lib_dir, "c3nif.c3l")

    unless File.exists?(c3nif_lib_path) do
      File.ln_s!(c3nif_src, c3nif_lib_path)
    end

    # Run c3c compiler
    case System.cmd("c3c", ["build"], cd: output_dir, stderr_to_stdout: true) do
      {_output, 0} ->
        lib_name = "#{module}#{C3nif.nif_extension()}"
        {:ok, Path.join([output_dir, "build", lib_name])}

      {output, exit_code} ->
        {:error, {:compile_failed, exit_code, output}}
    end
  end

  @doc """
  Returns the staging directory for a module's build files.
  """
  def staging_dir(module) do
    tmp_dir()
    |> Path.join(".c3nif_compiler")
    |> Path.join(to_string(module))
  end

  defp tmp_dir do
    System.tmp_dir!()
  end

  defp generate_project_json(module, _otp_app) do
    %{
      "langrev" => "1",
      "warnings" => ["no-unused"],
      "dependency-search-paths" => ["lib"],
      "dependencies" => ["c3nif"],
      "version" => "0.1.0",
      "sources" => ["#{module}.c3"],
      "output" => "build",
      "targets" => %{
        to_string(module) => %{
          "type" => "dynamic-lib",
          "reloc" => "pic"
        }
      },
      "cc" => "cc",
      "linker" => "cc",
      "link-libc" => true,
      "opt" => "O0"
    }
  end

  defp nif_name(module) do
    "lib#{module}"
  end

  defp c3nif_src_path do
    # In development, use the local c3nif.c3l directory
    # In production, use the installed path
    dev_path = Path.join([File.cwd!(), "c3nif.c3l"])

    if File.exists?(dev_path) do
      dev_path
    else
      Application.app_dir(:c3nif, ["priv", "c3nif.c3l"])
    end
  end
end
