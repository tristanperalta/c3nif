defmodule C3nif.SigilTest do
  use ExUnit.Case, async: true

  # This module tests that the sigil compiles correctly
  # The sigil must be used at module level (not inside functions)
  # because it sets module attributes

  describe "sigil_n/2" do
    test "sigil_n macro is exported and can be imported" do
      # Verify the sigil macro exists and is exported
      assert macro_exported?(C3nif, :sigil_n, 2)
    end

    test "sigil_n is a valid single-letter sigil name" do
      # This test verifies that ~n syntax works by checking the macro exists
      # The actual sigil usage is tested via the SigilUsageTest module below
      # which uses the sigil at module level
      assert {:sigil_n, 2} in C3nif.__info__(:macros)
    end
  end
end

# Test module that actually uses the sigil at module level
# This verifies that ~n"""...""" syntax compiles correctly
# (Previously ~c3 would fail with "invalid sigil delimiter: 3")
defmodule C3nif.SigilUsageTest do
  # Register the attribute so we can accumulate code parts
  Module.register_attribute(__MODULE__, :c3_code_parts, accumulate: true)

  # Import the sigil
  import C3nif, only: [sigil_n: 2]

  # Use the sigil - this is the critical test!
  # If Elixir's lexer doesn't support the sigil name, this will fail to compile
  ~n"""
  module sigil_test;

  fn void test_function() {
      // This is test C3 code
  }
  """

  # Also test other delimiters
  ~n(// inline code with parens)
  ~n[// inline code with brackets]
  ~n{// inline code with braces}

  # Verify the code was accumulated
  def get_code_parts do
    @c3_code_parts |> Enum.reverse() |> Enum.join()
  end
end

defmodule C3nif.SigilUsageVerificationTest do
  use ExUnit.Case, async: true

  alias C3nif.SigilUsageTest

  describe "sigil usage" do
    test "~n sigil accumulates code at module level" do
      code = SigilUsageTest.get_code_parts()

      assert code =~ "module sigil_test"
      assert code =~ "fn void test_function()"
      assert code =~ "inline code with parens"
      assert code =~ "inline code with brackets"
      assert code =~ "inline code with braces"
    end

    test "~n sigil adds file reference comments" do
      code = SigilUsageTest.get_code_parts()

      # The sigil adds // ref file:line comments
      assert code =~ "// ref"
      assert code =~ "sigil_test.exs"
    end
  end
end
