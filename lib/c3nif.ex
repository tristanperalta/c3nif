defmodule C3nif do
  @moduledoc """
  Write Erlang/Elixir NIFs in the C3 programming language.

  C3nif provides inline NIF support for [C3](https://c3-lang.org/), allowing you
  to write high-performance native code with type-safe conversions, automatic
  resource management, and comprehensive error handling.

  ## Basic Usage

  Add `use C3nif` to your module with the `:otp_app` option, then use the
  `~c3` sigil to write inline C3 code:

      defmodule MyNif do
        use C3nif, otp_app: :my_app

        ~c3\"\"\"
        module mynif;

        import c3nif;

        fn c3nif::ErlNifTerm add_one(
            c3nif::ErlNifEnv* raw_env,
            CInt argc,
            c3nif::ErlNifTerm* argv
        ) @nif {
            c3nif::Env e = c3nif::env::wrap(raw_env);
            c3nif::Term arg0 = c3nif::term::wrap(argv[0]);

            int? value = arg0.get_int(&e);
            if (catch err = value) {
                return c3nif::term::make_badarg(&e).raw();
            }

            return c3nif::term::make_int(&e, value + 1).raw();
        }
        \"\"\"
      end

  ## Options

  - `:otp_app` - Required. The OTP application this module belongs to.
  - `:c3_path` - Optional. Path to external C3 source file instead of inline code.
  - `:nifs` - Optional. List of NIF function specifications.

  ## C3 NIF Conventions

  - NIF functions should be marked with the `@nif` attribute
  - Use dirty schedulers with `@nif("name", dirty: .cpu)` or `dirty: .io`
  - Return `ErlNifTerm` from NIF functions
  - Use `c3nif::term::make_badarg()` for argument errors
  """

  @spec __using__(keyword) :: Macro.t()
  defmacro __using__(opts) do
    module = __CALLER__.module

    unless Keyword.has_key?(opts, :otp_app) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description:
          "(module #{inspect(module)}) you must supply an `otp_app` option to `use C3nif`"
    end

    Module.register_attribute(module, :c3_code_parts, accumulate: true)
    Module.register_attribute(module, :c3_code, persist: true)

    quote do
      @c3nif_opts unquote(opts)

      import C3nif, only: [sigil_c3: 2]
      @on_load :__load_nifs__
      @before_compile C3nif.Compiler
    end
  end

  @doc """
  Declares a string block to be included in the module's C3 source file.

  ## Example

      ~c3\"\"\"
      module mymodule;

      import c3nif;

      fn c3nif::ErlNifTerm my_nif(...) @nif {
          // NIF implementation
      }
      \"\"\"
  """
  defmacro sigil_c3({:<<>>, meta, [c3_code]}, []) do
    line = meta[:line]
    module = __CALLER__.module
    file = Path.relative_to_cwd(__CALLER__.file)

    quote bind_quoted: [module: module, c3_code: c3_code, file: file, line: line] do
      @c3_code_parts "// ref #{file}:#{line}\n"
      @c3_code_parts c3_code
      :nothing
    end
  end

  @doc """
  Retrieves the C3 code from any given module that was compiled with C3nif.
  """
  def code(module) do
    [code] = Keyword.fetch!(module.__info__(:attributes), :c3_code)
    code
  end

  @nif_extension (case :os.type() do
                    {:unix, :darwin} -> ".dylib"
                    {:unix, _} -> ".so"
                    {_, :nt} -> ".dll"
                  end)

  @doc """
  Returns the NIF library file extension for the current platform.
  """
  def nif_extension, do: @nif_extension

  @doc """
  Returns the path to the C3 source directory.
  """
  def c3_src_path do
    Application.app_dir(:c3nif, "c3_src")
  end
end
