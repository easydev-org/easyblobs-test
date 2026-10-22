defmodule EasyblobsTestHello.MixProject do
  use Mix.Project

  def project do
    [
      app: :easyblobs_test_hello,
      version: "1.0.0",
      elixir: "~> 1.15",
      description: "easyblobs e2e fixture",
      package: [licenses: ["Apache-2.0"]],
      deps: []
    ]
  end

  def application, do: [extra_applications: []]
end
