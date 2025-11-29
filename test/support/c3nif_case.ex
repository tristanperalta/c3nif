defmodule C3nif.Case do
  @moduledoc """
  Test case helpers for C3nif tests.

  Use this module in your test files to get access to common test helpers
  and setup for testing C3 NIFs.

  ## Example

      defmodule MyNifTest do
        use C3nif.Case

        test "my NIF works" do
          # test code
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import C3nif.Case
    end
  end

  setup_all do
    # Ensure C3 compiler is available
    case System.cmd("which", ["c3c"]) do
      {_, 0} -> :ok
      _ -> raise "c3c compiler not found in PATH"
    end

    :ok
  end

  @doc """
  Compiles a C3 NIF module for testing.

  Returns `{:ok, module}` on success or `{:error, reason}` on failure.

  ## Options

  - `:otp_app` - The OTP application (default: `:c3nif`)
  - `:skip_codegen` - If true, skip automatic entry point generation (default: true for backwards compatibility)
  """
  def compile_test_nif(module, c3_code, opts \\ []) do
    otp_app = Keyword.get(opts, :otp_app, :c3nif)
    # Default to skip_codegen: true for backwards compatibility with existing tests
    skip_codegen = Keyword.get(opts, :skip_codegen, true)

    compile_opts = [
      module: module,
      otp_app: otp_app,
      c3_code: c3_code,
      skip_codegen: skip_codegen
    ]

    C3nif.Compiler.compile(compile_opts)
  end

  @doc """
  Creates a temporary directory for test artifacts.
  """
  def tmp_test_dir(test_name) do
    dir =
      System.tmp_dir!()
      |> Path.join(".c3nif_test")
      |> Path.join(to_string(test_name))

    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Cleans up a temporary test directory.
  """
  def cleanup_test_dir(dir) do
    File.rm_rf!(dir)
  end
end
