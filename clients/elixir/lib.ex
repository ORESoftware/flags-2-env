defmodule Flags2Env do
  @moduledoc false

  def parse_process do
    :flags2env.parse_process()
  end

  def parse_process(config_path) do
    :flags2env.parse_process(config_path)
  end

  def parse(argv) do
    :flags2env.parse(argv)
  end

  def parse(argv, config_path) do
    :flags2env.parse(argv, config_path)
  end

  def apply_process(env \\ System.get_env()) do
    Map.merge(env, parse_process())
  end

  def apply(argv, env \\ System.get_env()) do
    Map.merge(env, parse(argv))
  end

  def apply(argv, env, config_path) do
    Map.merge(env, parse(argv, config_path))
  end

  def env_map do
    System.get_env()
  end
end
