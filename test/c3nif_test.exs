defmodule C3nifTest do
  use ExUnit.Case
  doctest C3nif

  describe "C3nif module" do
    test "nif_extension/0 returns correct extension for platform" do
      ext = C3nif.nif_extension()

      case :os.type() do
        {:unix, :darwin} -> assert ext == ".dylib"
        {:unix, _} -> assert ext == ".so"
        {_, :nt} -> assert ext == ".dll"
      end
    end
  end
end
