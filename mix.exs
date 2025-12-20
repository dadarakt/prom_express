defmodule PromExpress.MixProject do
  use Mix.Project

  def project do
    [
      app: :prom_express,
      version: "0.1.1",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Express route to PromEx metrics in your modules",
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/dadarakt/prom_express"
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.32", only: :dev, runtime: false},
      {:plug, "~> 1.18"},
      {:prom_ex, "~> 1.11"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
