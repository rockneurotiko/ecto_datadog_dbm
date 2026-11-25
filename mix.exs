defmodule EctoDatadogDbm.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/OWNER/ecto_datadog_dbm"

  def project do
    [
      app: :ecto_datadog_dbm,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Datadog Database Monitoring to APM trace linking for Ecto and Postgres",
      package: package(),
      docs: [main: "readme", extras: ["README.md", "CHANGELOG.md"]],
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:db_connection, ">= 0.0.0"},
      {:opentelemetry_api, "~> 1.4", optional: true},
      {:opentelemetry, "~> 1.5", only: :test},
      {:opentelemetry_process_propagator, "~> 0.3", only: :test},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
