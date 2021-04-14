{ config, lib, pkgs, ... }:
{
  # Configuration items that should be done prior to any per-plugin configuration
  prePluginConfig = ''
    let mapleader = "\<Space>"
    augroup vimrc
      autocmd!
    augroup END
    set termguicolors
  '';
  # General configuration items that are appended to the end of the generated
  # vimrc. You can use e.g. `lib.mkAfter` if you need something to go at the
  # very end of the file.
  extraConfig = ''
    set incsearch
    set hlsearch
    set ignorecase
    set smartcase
    set number
    set relativenumber
    set autoindent
    set shiftwidth=2
    set softtabstop=2
    set tabstop=2
    set expandtab

    " Use Ripgrep (rg) for search backend
    let g:ackprg = '${pkgs.ripgrep}/bin/rg --vimgrep --smart-case --no-heading --max-filesize=4M'
    set grepprg:${pkgs.ripgrep}/bin/rg\ --vimgrep\ --smart-case\ --no-heading\ --max-filesize=4M

    nnoremap <Leader>o :exe ':silent !${pkgs.xdg-utils}/bin/xdg-open % &'<CR>
  '';
  # A list of packages whose executables should be added to the $PATH for
  # neovim. These will *only* be added to neovim's path, not to the system or
  # user profiles.
  extraBinPackages = with pkgs; [
    silver-searcher
    xdg_utils # xdg-open
  ];
  # See chapter 3
  mergePlugins = true;
  # `files` can be used to build a symlink tree of files and folders, which
  # would typically consist of any extra/local contents of .config/nvim/ in a
  # non-Nix neovim setup.
  files = {
    neosnippets.source = "/my/snippet/files/";
  };
}
