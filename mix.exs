defmodule ODCounter.MixProject do
  use Mix.Project

  def version do
    "1.0.1"
  end

  def description do
    ":counters without ceremony"
  end

  def project do
    [
      app: :odcounter,
      version: version(),
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  defp package do
    [
      description: description(),
      licenses: ["BSD-2-Clause"],
      files: [
        "lib",
        "mix.exs",
        "README.md",
        ".formatter.exs"
      ],
      maintainers: [
        "hissssst"
      ],
      links: %{
        GitHub: "https://github.com/hissssst/odcounter",
        Changelog: "https://github.com/hissssst/odcounter/blob/main/CHANGELOG.md"
      }
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.28", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      source_ref: version(),
      main: "readme",
      extras: ["README.md"] ++ Path.wildcard("pages/*") ++ ["CHANGELOG.md"]
    ]
  end
end
