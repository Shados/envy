{ config, lib, pkgs, ... }:
{
  pluginRegistry = {
    # In this case, `source` is pointed to an existing Vim plugin derivation.
    "denite.nvim" = {
      enable = true;
      source = pkgs.vimPlugins.denite-nvim;
    };

    # In this case, Envy will dynamically construct a derivation using the
    # given Nix store path as the source.
    localPlugin = {
      enable = true;
      source = /some/local/path/or/store/path;
    };

    # Here we instead instruct Envy to have Vim load the plugin from a local
    # filesystem path at run-time, rather than bundling it into the Nix store.
    # This is useful for doing plugin development, or if you otherwise want to
    # use a plugin outside of the Nix store, while still allowing you to
    # leverage Envy's configuration and dependency specification/resolution
    # mechanisms.
    inDevPlugin = {
      enable = true;
      dir = "/a/local/path/string";
    };

    # Envy also provides a helper for constructing a vim plugin derivation from
    # a Niv sources.nix attrset, which you can then use as a source.
    vim-systemd-syntax = {
      enable = true;
      source = config.sn.programs.neovim.lib.buildVimPluginFromNiv (import ./pins { }) "vim-systemd-syntax";
    };
  };
}
