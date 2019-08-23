{ config, lib, pkgs, ... }:
{
  # Configfuration items that should or must precede everything else, including
  # per-plugin pre-plugin-load configuration items
  earlyConfig = ''
    let mapleader = "\<Space>"
    augroup vimrc
      autocmd!
    augroup END
  '';
  # Configuration items that should be done prior to loading any plugins (but
  # don't depend on any single plugin); there is also `postPluginConfig` for
  # configuration items that should be done after loading *all* plugins.
  prePluginConfig = ''
    set termguicolors
    syntax enable
  '';
  # General configuration items that don't have any specific ordering
  # requirements; these are appended to the generated init.vim file, so you can
  # use e.g. `lib.mkAfter` if you need something to go at the very end of the
  # file.
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

    " Use The Silver Searcher (ag) for search backend
    let g:ackprg = 'ag --nogroup --column'
    set grepprg:ag\ --nogroup\ --nocolor
    nnoremap <Leader>o :exe ':silent !xdg-open % &'<CR>
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
