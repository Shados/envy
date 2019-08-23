{ config, lib, pkgs, ... }:
{
  pluginRegistry = {
    # In this case, the name 'ale' is automatically 'resolved' against
    # pkgs.vimPlugins to select the plugin source
    ale.enable = true;
    # In this case, `source` is explicitly pointed to an existing Vim plugin
    # derivation.
    "denite.nvim" = {
      enable = true;
      source = pkgs.vimPlugins.denite-nvim;
    };
    # In this case, the name fails to resolve against pkgs.vimPlugins, so
    # `source` is automatically inferred from the `name`, on the assumption
    # that it is a vim-plug-compatible 'shortname', which will be used to
    # dynamically construct a derivation from a Vim plugin sourced from
    # https://github.com/Shados/vim-session (see chapter 3).
    "Shados/vim-session".enable = true;
    vim-buffet = {
      enable = true;
      # In this case, we again are using a shortname for the source, but we set
      # it explicitly.
      source = "bagrat/vim-buffet";
      # Additionally, we specify the exact commit we want to pin and use for the git source.
      # Generally you are better off relying on the separate JSON pin files to
      # pin to a specific commit, but in this case the version after this
      # commit has breaking changes, which would mean the configuration of the
      # plugin would also have to change, meaning that the commit information
      # is more an element of configuration than of state. 'branch' and 'tag'
      # are also supported for specifying what to fetch.
      commit = "044f2954a5e49aea8625973de68dda8750f1c42d";
    };
    localPlugin = {
      enable = true;
      # In this case, Envy will dynamically construct a derivation using the
      # given Nix store path as the source.
      source = /some/local/path/or/store/path;
    };
    inDevPlugin = {
      enable = true;
      # Here we instead instruct Envy to have Vim load the plugin from a local
      # filesystem path at run-time, rather than bundling it into the Nix
      # store. This is useful for doing plugin development, or if you otherwise
      # want to use a plugin outside of the Nix store, while still allowing you
      # to leverage Envy's configuration and dependency
      # specification/resolution mechanisms.
      dir = "/a/local/path/string";
    };
  };
}
