# Precompiled NIF Distribution

C3nif can ship prebuilt `.so` / `.dylib` / `.dll` archives so downstream
users don't need a `c3c` toolchain to install your library. This mirrors
the workflow of `rustler_precompiled` for Rust NIFs: you build once per
target on CI, upload the archives to a release URL, commit a checksum
manifest, and consumers get a fast, verified install.

## Concepts

- **Target triple** — short c3c target name like `linux-x64`,
  `macos-aarch64`, `windows-x64`. The consumer's host is detected at
  install time; you ship one archive per target you want to support.
- **Artifact archive** — `lib<Module>-<version>-<triple>.tar.gz`
  containing the compiled shared library.
- **Checksum manifest** — `checksum-<version>.exs` mapping each archive
  filename to its SHA-256 digest. This file is **committed into the
  consumer's repository** so downloads are verified end-to-end.

## Consumer opt-in

In a downstream project:

```elixir
defmodule MyApp.Nif do
  use C3nif,
    otp_app: :my_app,
    precompiled: [
      base_url: "https://github.com/me/my_app/releases/download/v0.1.0",
      version: "0.1.0",
      checksums_path: Path.expand("../../priv/checksum-0.1.0.exs", __DIR__)
    ]

  ~n"""
  module mynif;
  import c3nif;
  // ...
  """
end
```

At `mix compile` time, `Mix.Tasks.Compile.C3nif` will:

1. Detect the host triple (`linux-x64`, `macos-aarch64`, etc).
2. Load the checksum manifest and find the expected digest for
   `lib<Module>-<version>-<triple>.tar.gz`.
3. Download the archive from `{base_url}/{filename}` (cached under
   `$XDG_CACHE_HOME/c3nif_precompiled`).
4. Verify the SHA-256 against the manifest.
5. Extract the shared library into the OTP app's `priv/` directory.

If any step fails and `:force_build` is left at its default (`true`), the
compile falls back to a local `c3c` build. Set `:force_build` to `false`
to turn a fetch failure into a hard error.

## Maintainer workflow

As a library maintainer producing the artifacts:

1. **Build the matrix locally or in CI:**

   ```bash
   mix compile                    # populate the C3nif manifest
   mix c3nif.precompile           # builds for all default targets
   ```

   Default targets are returned by
   `C3nif.Precompiled.default_targets/0`. Override with `--target`:

   ```bash
   mix c3nif.precompile --target linux-x64 --target macos-aarch64
   ```

   Other useful flags:

   - `--module Elixir.MyApp.Nif` — build a single module
   - `--version 0.1.0` — override the version string (defaults to the
     OTP app's `mix.exs` version)
   - `--output-dir priv/precompiled` — where archives and checksums land

2. **Upload the archives** to your release hosting (e.g. a GitHub
   release tagged `v0.1.0`). The files are at
   `priv/precompiled/lib<Module>-<version>-<triple>.tar.gz`.

3. **Commit the checksum file.** The task writes
   `priv/precompiled/checksum-<version>.exs`. Commit this file into
   your repository. Consumers reference it via `:checksums_path`.

4. **Bump the version** for each release. The checksum file is
   version-pinned, so old consumers keep working.

## Cross-compilation notes

`mix c3nif.precompile` invokes `c3c build --target <triple>` for each
target. This relies on whatever cross toolchains are installed on the
build host — typically you'll run this inside a CI matrix where each
job has access to the right `clang` / `cc` for its target.

A minimal GitHub Actions setup might use the `matrix.include` strategy
to run one job per `(runner, target)` pair:

```yaml
strategy:
  matrix:
    include:
      - {runner: ubuntu-latest, target: linux-x64}
      - {runner: ubuntu-24.04-arm, target: linux-aarch64}
      - {runner: macos-13, target: macos-x64}
      - {runner: macos-14, target: macos-aarch64}
      - {runner: windows-latest, target: windows-x64}
```

Each job runs `mix c3nif.precompile --target ${{ matrix.target }}` and
uploads the resulting archive plus partial checksum file as an
artifact; a final "release" job merges the per-target checksum files
into a single `checksum-<version>.exs` and publishes everything to the
release.

## Troubleshooting

- **`unsupported_host`** — the consumer is running on a CPU/OS combo the
  library doesn't ship binaries for. They can either build from source
  (which is the default fallback) or file an issue asking for a new
  target in your next release.
- **Checksum mismatch** — either the hosted artifact was re-uploaded
  without bumping the version, or the download was corrupted. Delete the
  cached file under `$XDG_CACHE_HOME/c3nif_precompiled` and retry; if
  the mismatch persists, the artifact has been tampered with.
- **`checksum_entry_missing`** — the checksum manifest doesn't list the
  host's target. You need to re-run the precompile task with that
  target included and publish the updated manifest.
