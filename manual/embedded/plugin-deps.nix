{ config, lib, pkgs, ... }:
{
  pluginRegistry = {
    # Inter-plugin dependencies; the items should either be `pluginRegistry`
    # attribute names or vim plugin derivations.
    neosnippet-snippets.dependencies = [ "neosnippet-vim" ];
    # Specifies that a plugin needs external executables from the given
    # packages made available in neovim's $PATH.
    ale.binDeps = with pkgs; [
      bash
      shellcheck
      shfmt
    ];
    # Ensures that the specified Lua modules will be made available in
    # neovim's LUA_PATH/LUA_CPATH, meaning that the main neovim process can
    # load them for in-process Lua plugins and scripts to use.
    "Shados/precog.nvim".luaDeps = ps: with ps; [
      luafilesystem
    ];
    # Flags a plugin as being a 'remote' plugin requiring a plugin host for a
    # specific language (here, Python 3).
    denite-nvim.remote.python3 = true;
    # Pulls in plugin-host-language dependencies.
    # Automatically implies `remote.python3 = true;`.
    aPythonPlugin.remote.python3Deps = ps: with ps; [
      requests
    ];
  };
}
