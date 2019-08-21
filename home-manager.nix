{ enabled ? true, mergeNixosDefinitions ? false }:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.sn.programs.neovim;
  nvimLib = import ./lib.nix { nixpkgs = pkgs; };
  vimPkgModule = import ./module.nix pkgs;
in
{
  options = {
    sn.programs.neovim = mkOption {
      type = types.submodule vimPkgModule;
      default = {};
    };
  };
  config = mkIf enabled {
    home.packages = [
      cfg.wrappedNeovim
      (pkgs.callPackage ./envy-pins-package.nix { })
    ];
    sn.programs.neovim = mkIf (enabled && mergeNixosDefinitions) (
      mkMerge (nvimLib.nixosNvimConfig {
        nixpkgsPath = pkgs.path;
        configPath = nvimLib.nixosConfigPath;
      })
    );
  };
}
