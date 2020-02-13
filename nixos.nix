{ enabled ? true }:
{ config, lib, pkgs, ... }:
with lib;

let
  cfg = config.sn.programs.neovim;
  vimPkgModule = import ./module.nix pkgs;
in
{
  options = {
    sn.programs.neovim = mkOption {
      type = types.submodule vimPkgModule;
      default = {};
      description = ''
        Neovim configuration.
      '';
    };
  };
  config = mkIf enabled {
    environment.systemPackages = [
      cfg.wrappedNeovim
      (pkgs.callPackage ./envy-pins-package.nix { })
    ];
  };
}
