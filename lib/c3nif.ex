defmodule C3nif do
  @moduledoc """
  Write Erlang/Elixir NIFs in the C3 programming language.

  C3nif provides inline NIF support for [C3](https://c3-lang.org/), allowing you
  to write high-performance native code with type-safe conversions, automatic
  resource management, and comprehensive error handling.

  ## Basic Usage

  Add `use C3nif` to your module with the `:otp_app` option, then use the
  `~n` sigil (for "nif") to write inline C3 code:

      defmodule MyNif do
        use C3nif, otp_app: :my_app

        ~n\"\"\"
        module mynif;

        import c3nif;
        import c3nif::env;
        import c3nif::term;

        <* nif: arity = 1 *>
        fn ErlNifTerm add_one(
            ErlNifEnv* raw_env,
            CInt argc,
            ErlNifTerm* argv
        ) {
            Env e = env::wrap(raw_env);
            Term arg0 = term::wrap(argv[0]);

            int? value = arg0.get_int(&e);
            if (catch err = value) {
                return term::make_badarg(&e).raw();
            }

            return term::make_int(&e, value + 1).raw();
        }
        \"\"\"
      end

  ## Options

  - `:otp_app` - Required. The OTP application this module belongs to.
  - `:c3_path` - Optional. Path to external C3 source file instead of inline code.
  - `:c3_sources` - Optional. List of additional C3 source paths/globs to include (e.g., `["c3_src/mylib/src/**"]`).
  - `:nifs` - Optional. List of NIF function specifications.

  ## C3 NIF Conventions

  - NIF functions use `<* nif: arity = N *>` doc comment annotations
  - Use dirty schedulers with `<* nif: arity = N, dirty = cpu *>` or `dirty = io`
  - Return `ErlNifTerm` from NIF functions
  - Use `term::make_badarg()` for argument errors
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

      import C3nif, only: [sigil_n: 2]
      @on_load :__load_nifs__
      @before_compile C3nif.Compiler
    end
  end

  @doc """
  Declares a string block to be included in the module's C3 source file.

  The `~n` sigil (for "nif") allows you to write inline C3 code that will be
  compiled into a NIF library.

  ## Example

      ~n\"\"\"
      module mymodule;

      import c3nif;

      fn ErlNifTerm my_nif(...) @nif {
          // NIF implementation
      }
      \"\"\"

  Note: The sigil name is `~n` (single letter) because Elixir only supports
  single-letter sigil names.
  """
  defmacro sigil_n({:<<>>, meta, [c3_code]}, []) do
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
