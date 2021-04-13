# To-Do List
- [x] Pre-build config-nvim-builder.lua from the MoonScript source
- [ ] Migrate envy-pins to being a real package, poetry-based?
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
- [ ] Support pure-Lua nvimrc
- [ ] Support MoonScript nvimrc
- [ ] Support Ruby-based remote plugins?
- [ ] Support NodeJS-based remote plugins?
