defmodule C3nif.PrecompiledTest do
  use ExUnit.Case, async: true

  alias C3nif.Precompiled

  describe "target_triple/0" do
    test "returns a host triple for the running VM" do
      assert {:ok, triple} = Precompiled.target_triple()

      assert triple in [
               "linux-x64",
               "linux-aarch64",
               "macos-x64",
               "macos-aarch64",
               "windows-x64",
               "windows-aarch64"
             ]
    end
  end

  describe "default_targets/0" do
    test "includes the five common distribution triples" do
      targets = Precompiled.default_targets()
      assert "linux-x64" in targets
      assert "linux-aarch64" in targets
      assert "macos-x64" in targets
      assert "macos-aarch64" in targets
      assert "windows-x64" in targets
    end
  end

  describe "lib_extension/1" do
    test "maps linux targets to .so" do
      assert Precompiled.lib_extension("linux-x64") == ".so"
      assert Precompiled.lib_extension("linux-aarch64") == ".so"
    end

    test "maps macos targets to .dylib" do
      assert Precompiled.lib_extension("macos-x64") == ".dylib"
      assert Precompiled.lib_extension("macos-aarch64") == ".dylib"
    end

    test "maps windows targets to .dll" do
      assert Precompiled.lib_extension("windows-x64") == ".dll"
    end
  end

  describe "artifact_name/3" do
    test "produces a conventional archive filename" do
      assert Precompiled.artifact_name("Elixir.Foo.Nif", "1.2.3", "linux-x64") ==
               "libElixir.Foo.Nif-1.2.3-linux-x64.tar.gz"
    end
  end

  describe "file_checksum/1" do
    @tag :tmp_dir
    test "computes sha256 over a file's contents", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "payload.bin")
      File.write!(path, "hello world")

      # sha256("hello world") — known value from any sha256 utility.
      assert Precompiled.file_checksum(path) ==
               "sha256:b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
    end
  end

  describe "load_checksums/1" do
    @tag :tmp_dir
    test "parses an exs manifest into a map", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "checksum-0.1.0.exs")

      File.write!(path, """
      %{
        "libFoo-0.1.0-linux-x64.tar.gz" => "sha256:deadbeef",
        "libFoo-0.1.0-macos-x64.tar.gz" => "sha256:cafebabe"
      }
      """)

      assert {:ok, map} = Precompiled.load_checksums(path)
      assert map["libFoo-0.1.0-linux-x64.tar.gz"] == "sha256:deadbeef"
      assert map["libFoo-0.1.0-macos-x64.tar.gz"] == "sha256:cafebabe"
    end

    test "returns an error when the file is missing" do
      assert {:error, {:checksum_missing, _}} = Precompiled.load_checksums("/nope/nope.exs")
    end
  end

  describe "verify_checksum!/2" do
    @tag :tmp_dir
    test "passes when the digest matches", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "a.bin")
      File.write!(path, "hello world")
      expected = Precompiled.file_checksum(path)
      assert :ok = Precompiled.verify_checksum!(path, expected)
    end

    @tag :tmp_dir
    test "raises when the digest does not match", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "a.bin")
      File.write!(path, "hello world")

      assert_raise RuntimeError, ~r/checksum mismatch/, fn ->
        Precompiled.verify_checksum!(path, "sha256:0000")
      end
    end
  end

  describe "extract!/2 round trip" do
    @tag :tmp_dir
    test "packs and unpacks a library file", %{tmp_dir: tmp_dir} do
      payload = Path.join(tmp_dir, "libFoo.so")
      File.write!(payload, "fake so contents")

      archive = Path.join(tmp_dir, "libFoo-1.0.0-linux-x64.tar.gz")

      :ok =
        :erl_tar.create(
          to_charlist(archive),
          [{~c"libFoo.so", to_charlist(payload)}],
          [:compressed]
        )

      dest_dir = Path.join(tmp_dir, "extracted")
      [lib_path] = Precompiled.extract!(archive, dest_dir)
      assert File.read!(lib_path) == "fake so contents"
    end
  end
end
