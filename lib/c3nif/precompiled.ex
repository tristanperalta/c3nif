defmodule C3nif.Precompiled do
  @moduledoc """
  Fetch and verify precompiled C3 NIF artifacts.

  When a module uses `use C3nif, otp_app: ..., precompiled: [base_url: ..., version: ...]`,
  this module checks whether a prebuilt shared library is available for the host
  target. If present, it is downloaded (or taken from the local cache), SHA-256
  verified against a checksum manifest, and extracted into the OTP app's `priv/`
  directory — skipping the `c3c` source compile entirely.

  This mirrors the workflow established by `rustler_precompiled` for Rust NIFs:
  maintainers run `mix c3nif.precompile` to produce a per-target matrix of
  archives and a `checksum-<version>.exs` file, then upload both to a release
  hosting URL. Consumers add the checksum file to their repository so installs
  fail loudly when an artifact has been tampered with.

  ## Host triple

  Target triples match the short names reported by `c3c --list-targets`:

    * `linux-x64`, `linux-aarch64`
    * `macos-x64`, `macos-aarch64`
    * `windows-x64`, `windows-aarch64`

  `target_triple/0` maps the current BEAM host to one of these. Pass it into
  `artifact_name/3` to derive the expected archive filename.
  """

  @default_targets ~w(
    linux-x64
    linux-aarch64
    macos-x64
    macos-aarch64
    windows-x64
  )

  @doc """
  Default target triples for the precompile matrix.
  """
  def default_targets, do: @default_targets

  @doc """
  Return the c3c target triple for the current host, or `{:error, reason}` if
  the host isn't a supported combination.
  """
  def target_triple do
    arch = :erlang.system_info(:system_architecture) |> to_string()

    os =
      case :os.type() do
        {:unix, :linux} -> :linux
        {:unix, :darwin} -> :macos
        {:win32, _} -> :windows
        other -> {:unsupported_os, other}
      end

    cpu =
      cond do
        arch =~ ~r/^(x86_64|amd64)/ -> :x64
        arch =~ ~r/^(aarch64|arm64)/ -> :aarch64
        true -> {:unsupported_cpu, arch}
      end

    case {os, cpu} do
      {os, cpu} when is_atom(os) and is_atom(cpu) ->
        {:ok, "#{os}-#{cpu}"}

      {{:unsupported_os, detail}, _} ->
        {:error, {:unsupported_host, os: detail}}

      {_, {:unsupported_cpu, detail}} ->
        {:error, {:unsupported_host, arch: detail}}
    end
  end

  @doc """
  Return the shared-library extension for a given target triple.
  """
  def lib_extension("linux-" <> _), do: ".so"
  def lib_extension("macos-" <> _), do: ".dylib"
  def lib_extension("windows-" <> _), do: ".dll"

  @doc """
  Derive the archive filename for a module + version + target triple.

  Example: `artifact_name("Elixir.MyApp.Nif", "0.1.0", "linux-x64")` →
  `"libElixir.MyApp.Nif-0.1.0-linux-x64.tar.gz"`.
  """
  def artifact_name(module, version, triple) do
    "lib#{module}-#{version}-#{triple}.tar.gz"
  end

  @doc """
  Return the local cache directory where downloaded archives are stored.
  Honors the `XDG_CACHE_HOME` env var, falling back to `~/.cache`.
  """
  def cache_dir do
    base =
      case System.get_env("XDG_CACHE_HOME") do
        nil -> Path.join(System.user_home!(), ".cache")
        path -> path
      end

    Path.join(base, "c3nif_precompiled")
  end

  @doc """
  Load and parse a `checksum-<version>.exs` manifest file.

  The file is expected to evaluate to a map of `filename => "sha256:<hex>"`.
  Returns `{:ok, map}` on success or `{:error, reason}` otherwise.
  """
  def load_checksums(path) do
    if File.exists?(path) do
      try do
        {map, _} = Code.eval_file(path)
        {:ok, map}
      rescue
        e -> {:error, {:checksum_parse_failed, Exception.message(e)}}
      end
    else
      {:error, {:checksum_missing, path}}
    end
  end

  @doc """
  Compute the `"sha256:<hex>"` checksum of a file.
  """
  def file_checksum(path) do
    hash =
      path
      |> File.stream!([], 64 * 1024)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    "sha256:#{hash}"
  end

  @doc """
  Verify that a file's SHA-256 matches the expected checksum from a manifest.
  """
  def verify_checksum!(path, expected) do
    actual = file_checksum(path)

    if actual == expected do
      :ok
    else
      raise """
      Precompiled artifact checksum mismatch for #{path}.

        expected: #{expected}
        actual:   #{actual}

      Refusing to load a tampered artifact. Either update the checksum file
      or rebuild from source.
      """
    end
  end

  @doc """
  Download an artifact from `url` into the local cache and return its path.
  If already cached, skip the download.
  """
  def download(url, filename) do
    File.mkdir_p!(cache_dir())
    dest = Path.join(cache_dir(), filename)

    if File.exists?(dest) do
      {:ok, dest}
    else
      {:ok, _} = Application.ensure_all_started(:inets)
      {:ok, _} = Application.ensure_all_started(:ssl)

      # Reference :public_key functions via apply/3 to avoid compile-time
      # warnings when the module isn't loaded yet.
      pk = :public_key

      http_opts = [
        ssl: [
          verify: :verify_peer,
          cacerts: apply(pk, :cacerts_get, []),
          depth: 3,
          customize_hostname_check: [
            match_fun: apply(pk, :pkix_verify_hostname_match_fun, [:https])
          ]
        ]
      ]

      case :httpc.request(:get, {to_charlist(url), []}, http_opts, body_format: :binary) do
        {:ok, {{_, 200, _}, _headers, body}} ->
          File.write!(dest, body)
          {:ok, dest}

        {:ok, {{_, status, _}, _headers, _body}} ->
          {:error, {:download_failed, status, url}}

        {:error, reason} ->
          {:error, {:download_failed, reason, url}}
      end
    end
  end

  @doc """
  Extract a `.tar.gz` archive into a destination directory.
  Returns the list of extracted file paths.
  """
  def extract!(archive_path, dest_dir) do
    File.mkdir_p!(dest_dir)
    :ok = :erl_tar.extract(to_charlist(archive_path), [:compressed, {:cwd, to_charlist(dest_dir)}])

    archive_path
    |> list_archive_entries()
    |> Enum.map(&Path.join(dest_dir, &1))
  end

  defp list_archive_entries(archive_path) do
    {:ok, entries} =
      :erl_tar.table(to_charlist(archive_path), [:compressed])

    Enum.map(entries, &to_string/1)
  end

  @doc """
  Try to install a precompiled artifact into `priv/` for the given module.

  ## Options

    * `:module` — the module whose NIF is being installed
    * `:otp_app` — the OTP app (used to locate `priv/`)
    * `:base_url` — the URL prefix where artifacts are hosted
    * `:version` — the version string used in the artifact filename
    * `:checksums_path` — absolute path to the checksum manifest `.exs`
    * `:nif_basename` — the base filename without extension (e.g. `libElixir.MyApp.Nif`)

  Returns `{:ok, dest_path}` on success, `{:error, reason}` otherwise. Callers
  should fall back to source compilation when this returns an error.
  """
  def try_install(opts) do
    with {:ok, triple} <- target_triple(),
         version = Keyword.fetch!(opts, :version),
         module = Keyword.fetch!(opts, :module),
         base_url = Keyword.fetch!(opts, :base_url),
         nif_basename = Keyword.fetch!(opts, :nif_basename),
         filename = artifact_name(module, version, triple),
         url = String.trim_trailing(base_url, "/") <> "/" <> filename,
         {:ok, checksums} <- load_checksums(Keyword.fetch!(opts, :checksums_path)),
         {:ok, expected} <- fetch_expected(checksums, filename),
         {:ok, archive_path} <- download(url, filename),
         :ok <- verify_checksum!(archive_path, expected) do
      priv_dir = Keyword.fetch!(opts, :priv_dir)
      File.mkdir_p!(priv_dir)
      [lib_path | _] = extract!(archive_path, priv_dir)

      ext = lib_extension(triple)
      dest_name = nif_basename <> ext
      dest_path = Path.join(priv_dir, dest_name)

      unless Path.basename(lib_path) == dest_name do
        File.cp!(lib_path, dest_path)
      end

      {:ok, dest_path}
    end
  end

  defp fetch_expected(checksums, filename) do
    case Map.fetch(checksums, filename) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:checksum_entry_missing, filename}}
    end
  end
end
