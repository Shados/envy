{ nixpkgs ? import <nixpkgs> { }
}:
let
  inherit (nixpkgs.lib) attrNames elem evalModules filter filterAttrs hasAttr hasAttrByPath hasSuffix last listToAttrs mapAttrs mkDefault mkOverride nameValuePair optionalAttrs optionals removeSuffix replaceStrings splitString;
  getNvimSubmoduleDefs = options: options.sn.programs.neovim.definitions;
in
rec {
  # Builds a neovim module configuration.
  # NOTE: This may evaluate the current system's NixOS and/or home-manager
  # configurations, and if it does, it uses the nixpkgs and home-manager paths
  # that are given to it -- which may not necessarily be the ones used outside
  # of this.
  configuredNeovimModule = { pkgs ? nixpkgs, nvimConfig }: let
    nixpkgsPath = pkgs.path;
    cfg = (evalModules {
      modules = [
        ({ ... }: { _module.args.pkgs = pkgs; })
        nvimConfig nvimModule
      ];
    }).config;
  in cfg;

  nvimModule = import ./module.nix nixpkgs;

  buildVimPluginFromNiv = pins: pluginName: let
    pin = pins.${pluginName};
  in nixpkgs.vimUtils.buildVimPlugin (rec {
    name = "${pname}-${version}";
    pname = last (splitString "/" pluginName);
    version = pin.version or "unstable-${pin.rev}";
    src = pin;
  });
}
