# FIXME not a working module rn
{ config, lib, options, pkgs, ... }:
with lib;

let
  nixosOptions = options;
  hmModule = { config, lib, options, pkgs, ... }: let
    cfg = config.sn.programs.neovim;
  in {
    options = {
      sn.programs.neovim = {
        enable = mkEnableOption "Neovim";
        package = mkOption {
          type = with types; package;
          default = pkgs.neovim-unwrapped;
          defaultText = "pkgs.neovim-unwrapped";
          description = "The package to use for the neovim binary.";
        };

        nvimConfig = let
          vimPkgModule = import ./module.nix pkgs cfg.package;
        in mkOption {
          type = types.submodule vimPkgModule;
          description = ''
            Neovim configuration, plugins, and their associated configuration.
          '';
        };

        mergeNixosDefinitions = mkOption {
          type = with types; bool;
          default = false;
          description = ''
            Whether or not to merge in NixOS-based sn.programs.neovim settings.
          '';
        };
      };
    };

    config = mkIf cfg.enable {
      home.packages = [ cfg.nvimConfig.wrappedNeovim ];
      home.sessionVariables.NIXOS_HM_NVIM_ENABLED = "true";
      sn.programs.neovim.nvimConfig = mkIf cfg.mergeNixosDefinitions (mkMerge nixosOptions.sn.programs.neovim.nvimConfig.definitions);
    };
  };
in
{
  options = {
    home-manager.users = mkOption {
      # Submodule declarations get merged, so this will be merged in with the
      # upstream home-manager submodule definition :)
      type = with lib.types; attrsOf (submodule hmModule);
    };
  };
  config = {
    environment.profiles = mkBefore [
      "$HOME/.nix-profile"
      "/etc/profiles/per-user/$USER"
    ];
  };
}
