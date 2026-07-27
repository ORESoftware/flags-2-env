{ pkgs, agentCheck }:
let
  shellPackages =
    (with pkgs; [
      actionlint
      binutils
      gcc
      git
      gnumake
      jq
      just
      nixfmt-rfc-style
      nodejs_22
      pkg-config
      python3
      ruby
      shellcheck
      shfmt
    ])
    ++ [ agentCheck ];
in
pkgs.mkShell {
  packages = shellPackages;

  LANG = if pkgs.stdenv.hostPlatform.isDarwin then "en_US.UTF-8" else "C.UTF-8";
  LC_ALL = if pkgs.stdenv.hostPlatform.isDarwin then "en_US.UTF-8" else "C.UTF-8";

  shellHook = ''
    export NIX_DEV_SHELL=flags-2-env
    export NIX_AGENT_CACHE_ROOT="''${NIX_AGENT_CACHE_ROOT:-$PWD/.cache/nix-agent}"
    export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$NIX_AGENT_CACHE_ROOT/xdg}"
    export npm_config_cache="''${npm_config_cache:-$NIX_AGENT_CACHE_ROOT/npm}"
    export npm_config_nodedir="''${npm_config_nodedir:-${pkgs.nodejs_22}}"
    mkdir -p "$XDG_CACHE_HOME" "$npm_config_cache"
  '';
}
