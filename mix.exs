defmodule C3nif.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/tristanperalta/c3nif"

  def project do
    [
      app: :c3nif,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),

      # Docs
      name: "C3nif",
      description: "Write Erlang/Elixir NIFs in the C3 programming language",
      source_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "guides/nif-functions.md": [title: "NIF Functions"],
        "guides/type-conversion.md": [title: "Type Conversion"],
        "guides/error-handling.md": [title: "Error Handling"],
        "guides/resources.md": [title: "Resource Management"],
        "guides/dirty-schedulers.md": [title: "Dirty Schedulers"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [C3nif, C3nif.Compiler],
        Internals: [C3nif.Parser, C3nif.Generator]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib c3nif.c3l mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/project.plt"},
      plt_add_apps: [:mix]
    ]
  end

  defp aliases do
    # Only apply compile/test aliases when c3nif is the root project.
    # When used as a dependency, these aliases would interfere with
    # the parent project's compilation.
    if Mix.Project.config()[:app] == :c3nif do
      [
        compile: ["compile.c3nif", "compile"],
        test: ["compile.c3nif", "test"]
      ]
    else
      []
    end
  end
end
