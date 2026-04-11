defmodule C3nif.IntegrationTest.PrecompileTaskTest do
  # Smoke test for `mix c3nif.precompile`: inject a minimal NIF manifest
  # entry, run the task for the host triple, and verify that an archive
  # plus a checksum manifest are produced in the output directory.
  use ExUnit.Case, async: false

  alias C3nif.Compiler
  alias C3nif.Precompiled

  @moduletag :integration

  @fixture_module :"Elixir.C3nif.IntegrationTest.PrecompileFixture"

  @c3_code """
  module precompile_fixture;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;

  fn ErlNifTerm just_one(ErlNifEnv* env_raw, CInt argc, ErlNifTerm* argv) {
      Env e = env::wrap(env_raw);
      return term::make_int(&e, 1).raw();
  }

  ErlNifFunc[1] nif_funcs = {
      { .name = "just_one", .arity = 0, .fptr = &just_one, .flags = 0 },
  };

  ErlNifEntry nif_entry;

  fn ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.PrecompileFixture",
          &nif_funcs,
          1,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup do
    # Inject a minimal manifest entry so the task has something to build.
    manifest_path = Compiler.manifest_path()
    File.mkdir_p!(Path.dirname(manifest_path))

    existing =
      if File.exists?(manifest_path) do
        manifest_path |> File.read!() |> :erlang.binary_to_term()
      else
        %{}
      end

    entry = %{
      module: @fixture_module,
      otp_app: :c3nif,
      c3_code: @c3_code,
      c3_sources: [],
      source_file: "nofile",
      timestamp: System.os_time(:second)
    }

    updated = Map.put(existing, @fixture_module, entry)
    File.write!(manifest_path, :erlang.term_to_binary(updated))

    tmp_output = Path.join(System.tmp_dir!(), "c3nif_precompile_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_output)

    on_exit(fn ->
      # Remove the fixture entry but leave real consumers' entries intact.
      if File.exists?(manifest_path) do
        current = manifest_path |> File.read!() |> :erlang.binary_to_term()
        File.write!(manifest_path, :erlang.term_to_binary(Map.delete(current, @fixture_module)))
      end

      File.rm_rf!(tmp_output)
    end)

    {:ok, tmp_output: tmp_output}
  end

  test "mix c3nif.precompile builds an archive + checksum for the host triple", %{
    tmp_output: tmp_output
  } do
    {:ok, host_triple} = Precompiled.target_triple()

    Mix.Tasks.C3nif.Precompile.run([
      "--target",
      host_triple,
      "--module",
      to_string(@fixture_module),
      "--version",
      "99.0.0-test",
      "--output-dir",
      tmp_output
    ])

    archive_name = Precompiled.artifact_name(@fixture_module, "99.0.0-test", host_triple)
    archive_path = Path.join(tmp_output, archive_name)
    checksum_path = Path.join(tmp_output, "checksum-99.0.0-test.exs")

    assert File.exists?(archive_path), "expected archive at #{archive_path}"
    assert File.exists?(checksum_path), "expected checksum manifest at #{checksum_path}"

    {:ok, checksums} = Precompiled.load_checksums(checksum_path)
    assert Map.has_key?(checksums, archive_name)

    # The recorded digest must match a fresh hash of the archive on disk.
    assert checksums[archive_name] == Precompiled.file_checksum(archive_path)

    # The archive must be a valid tar.gz containing at least one entry.
    {:ok, entries} = :erl_tar.table(to_charlist(archive_path), [:compressed])
    refute Enum.empty?(entries)
  end
end
