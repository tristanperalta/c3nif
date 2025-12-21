defmodule C3nif.CompilerTest do
  use C3nif.Case, async: false

  alias C3nif.Compiler

  describe "compile/1" do
    test "compiles a minimal C3 NIF" do
      c3_code = """
      module test_nif;

      import c3nif::erl_nif;

      // Minimal NIF entry point for testing
      fn erl_nif::ErlNifEntry* nif_init() @export("nif_init") {
          return null;
      }
      """

      result = compile_test_nif(TestNif, c3_code)

      case result do
        {:ok, path} ->
          assert File.exists?(path)
          # Clean up
          File.rm(path)

        {:error, {:compile_failed, _exit_code, output}} ->
          flunk("Compilation failed: #{output}")
      end
    end
  end

  describe "staging_dir/1" do
    test "returns a path in tmp directory" do
      dir = Compiler.staging_dir(SomeModule)
      assert String.contains?(dir, "c3nif_compiler")
      assert String.contains?(dir, "SomeModule")
    end
  end
end
