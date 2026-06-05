defmodule Flags2Env.MixProject do
  use Mix.Project

  def project do
    [
      app: :flags2env,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: ["."],
      erlc_paths: ["native"],
      package: package(),
      description: "Elixir bindings for flags2env"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp package do
    [
      name: "flags2env_elixir",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/ORESoftware/flags-2-env"},
      files: [
        "lib.ex",
        "README.md",
        "LICENSE",
        "mix.exs",
        "native/flags2env.erl",
        "native/flags2env_nif.c",
        "native/parser.c",
        "native/parser.h"
      ]
    ]
  end
end
