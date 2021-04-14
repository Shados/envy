# To-Do List
- [x] Pre-build config-nvim-builder.lua from the MoonScript source
- [ ] Migrate envy-pins to being a real package, poetry-based?
    - [ ] Make it a separately-installable attribute, to still avoid the
      install space cost, and document how to run it with `nix run`
- [ ] Expose as a flake?
- [ ] Add tests where appropriate
    - [ ] Include a comprehensive example file in the book, which is itself tested
    - [ ] CT testin
- [ ] Collect the hm/nixos/manual/etc. files into attributes off of a single file?
- [x] Remove reliance on vim-plug by loading plugins ourselves; just *be* the
  plugin manager already \o/
- [ ] Lazy-loading support
    - [x] On filetype load
    - [x] On <Plug> mapping
    - [x] On command
    - [ ] On Lua require?
    - [ ] On global Lua function call?
    - [ ] Throw a User event per-plugin on lazy loading, with a per-plugin
      option to use this from the Nix module
    - [ ] Track and account for outside runtimepath modifications, allowing
      lazy-loading to be compatible with the simultaneous use of some other
      plugin manager
- [x] Support pure-Lua nvimrc
- [ ] Support MoonScript nvimrc
- [ ] Support Fennel nvimrc, for the hell of it?
- [ ] Support Ruby-based remote plugins?
- [ ] Support NodeJS-based remote plugins?
- [ ] Detect and emit warnings for file collisions in config-nvim-builder
    - [ ] If we do see non-trivial (e.g. readme.md) collisions in the wild,
      look into detecting collisions in module.nix and disabling individual
      plugin merging as a result?
- [ ] Improve the documentation with comprehensive option examples
- [ ] Fix old details in the manual
- [ ] Add a readme; mostly just point to the hosted docs
- [x] Re-add pre-/post-plugin extraConfig; although this isn't required
  per-plugin, it can be useful overall
- [ ] Properly hide debug options etc.
- [ ] Expand the Lua runtime to provide some convenience functions, 0.4/0.5
  cross-compatibility functions, etc.?
