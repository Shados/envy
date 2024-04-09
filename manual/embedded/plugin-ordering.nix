{ config, lib, pkgs, ... }:
{
  pluginRegistry = {
    # vim-devicons needs to be loaded after these plugins, if they
    # are being used, as per its installation guide.
    # Both `after` and `before` can be specified as either `pluginRegistry`
    # attribute names or vim plugin derivations.
    vim-devicons.after = [
      "nerdtree" "vim-airline" "ctrlp-vim" "powerline/powerline" "denite-nvim"
      "unite-vim" "lightline-vim" "vim-startify" "vimfiler" "vim-flagship"
    ];
  };
}
