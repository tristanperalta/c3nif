defmodule C3nif.GeneratorTest do
  use ExUnit.Case, async: true

  alias C3nif.Generator
  alias C3nif.Parser.{Callbacks, NifFunction}

  describe "generate_entry/3" do
    test "generates entry for single NIF" do
      nifs = [
        %NifFunction{c3_name: "add", elixir_name: "add", arity: 2, dirty: nil, line: 10}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      result = Generator.generate_entry("Elixir.MyNif", nifs, callbacks)

      assert result =~ "AUTO-GENERATED NIF ENTRY"
      assert result =~ ~s[.name = "add"]
      assert result =~ ".arity = 2"
      assert result =~ ".fptr = &add"
      assert result =~ ".flags = 0"
      assert result =~ "ErlNifFunc[1]"
      assert result =~ ~s["Elixir.MyNif"]
    end

    test "generates entry for multiple NIFs" do
      nifs = [
        %NifFunction{c3_name: "add", elixir_name: "add", arity: 2, dirty: nil, line: 10},
        %NifFunction{c3_name: "sub", elixir_name: "subtract", arity: 2, dirty: nil, line: 20},
        %NifFunction{c3_name: "mul", elixir_name: "mul", arity: 2, dirty: nil, line: 30}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      result = Generator.generate_entry("Elixir.Math", nifs, callbacks)

      assert result =~ "ErlNifFunc[3]"
      assert result =~ ~s[.name = "add"]
      assert result =~ ~s[.name = "subtract"]
      assert result =~ ~s[.name = "mul"]
      assert result =~ ".fptr = &add"
      assert result =~ ".fptr = &sub"
      assert result =~ ".fptr = &mul"
    end

    test "generates dirty CPU flag" do
      nifs = [
        %NifFunction{c3_name: "compute", elixir_name: "compute", arity: 1, dirty: :cpu, line: 10}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      result = Generator.generate_entry("Elixir.Heavy", nifs, callbacks)

      assert result =~ "erl_nif::ERL_NIF_DIRTY_JOB_CPU_BOUND"
    end

    test "generates dirty IO flag" do
      nifs = [
        %NifFunction{c3_name: "read", elixir_name: "read", arity: 1, dirty: :io, line: 10}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      result = Generator.generate_entry("Elixir.IO", nifs, callbacks)

      assert result =~ "erl_nif::ERL_NIF_DIRTY_JOB_IO_BOUND"
    end

    test "generates with on_load callback" do
      nifs = [
        %NifFunction{c3_name: "func", elixir_name: "func", arity: 0, dirty: nil, line: 10}
      ]

      callbacks = %Callbacks{on_load: "on_load", on_unload: nil}

      result = Generator.generate_entry("Elixir.WithLoad", nifs, callbacks)

      assert result =~ "&on_load"
      # unload should be null
      assert result =~ ~r/&on_load,\s*\n\s*null/
    end

    test "generates with on_unload callback" do
      nifs = [
        %NifFunction{c3_name: "func", elixir_name: "func", arity: 0, dirty: nil, line: 10}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: "on_unload"}

      result = Generator.generate_entry("Elixir.WithUnload", nifs, callbacks)

      assert result =~ "&on_unload"
      # load should be null
      assert result =~ ~r/null,\s*\n\s*&on_unload/
    end

    test "generates with both callbacks" do
      nifs = [
        %NifFunction{c3_name: "func", elixir_name: "func", arity: 0, dirty: nil, line: 10}
      ]

      callbacks = %Callbacks{on_load: "on_load", on_unload: "on_unload"}

      result = Generator.generate_entry("Elixir.Full", nifs, callbacks)

      assert result =~ "&on_load"
      assert result =~ "&on_unload"
    end

    test "generates nif_init with export attribute" do
      nifs = [
        %NifFunction{c3_name: "func", elixir_name: "func", arity: 0, dirty: nil, line: 10}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      result = Generator.generate_entry("Elixir.Test", nifs, callbacks)

      assert result =~ ~s[@export("nif_init")]
      assert result =~ "fn ErlNifEntry* nif_init()"
      assert result =~ "return &__c3nif_entry__"
    end

    test "raises error for empty NIF list" do
      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      assert_raise ArgumentError, ~r/No NIF functions found/, fn ->
        Generator.generate_entry("Elixir.Empty", [], callbacks)
      end
    end
  end

  describe "generate_complete/4" do
    test "appends entry to user code" do
      user_code = """
      module test;
      import c3nif;

      fn ErlNifTerm add(
          ErlNifEnv* env, CInt argc, ErlNifTerm* argv
      ) { return 0; }
      """

      nifs = [
        %NifFunction{c3_name: "add", elixir_name: "add", arity: 2, dirty: nil, line: 5}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      result = Generator.generate_complete(user_code, "Elixir.Test", nifs, callbacks)

      # User code should be at the start
      assert String.starts_with?(result, "module test;")

      # Entry code should be appended
      assert result =~ "AUTO-GENERATED NIF ENTRY"
      assert result =~ "__c3nif_funcs__"
      assert result =~ "nif_init"
    end

    test "preserves user code exactly" do
      user_code = "module test;\n\n// My comment\nfn void foo() {}"

      nifs = [
        %NifFunction{c3_name: "bar", elixir_name: "bar", arity: 0, dirty: nil, line: 1}
      ]

      callbacks = %Callbacks{on_load: nil, on_unload: nil}

      result = Generator.generate_complete(user_code, "Elixir.Test", nifs, callbacks)

      assert result =~ user_code
    end
  end
end
