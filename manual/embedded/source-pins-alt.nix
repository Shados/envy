{ config, lib, pkgs, ... }:
let
  envy = (builtins.fetchgit { url = https://github.com/Shados/envy; ref = "master"; });
  envyLib = import "${envy}/lib.nix" { nixpkgs = pkgs; };
in
{
  sourcePins = lib.fillPinsFromDir /directory/of/envy-pins/output/;
}

