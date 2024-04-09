{ enabled ? true }:
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types;
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
    home.packages = [
      cfg.wrappedNeovim
    ];
  };
}
