# To-Do List
- [ ] Expose as a flake?
- [ ] Add tests where appropriate
    - [ ] Include a comprehensive example file in the book, which is itself tested
    - [ ] CT testin
- [ ] Collect the hm/nixos/manual/etc. files into attributes off of a single file?
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
- [ ] Support Fennel nvimrc, for the hell of it?
- [ ] Support YueScript nvimrc, for the hell of it?
- [ ] Support Ruby-based remote plugins?
- [ ] Support NodeJS-based remote plugins?
- [ ] Detect and emit warnings for file collisions in config-nvim-builder
    - [ ] If we do see non-trivial (e.g. readme.md) collisions in the wild,
      look into detecting collisions in module.nix and disabling individual
      plugin merging as a result?
- [ ] Improve the documentation with comprehensive option examples
- [ ] Add a readme; mostly just point to the hosted docs
- [ ] Determine the impact of compileMoon's jankiness on eval times
- [ ] See issue #3 and finish deprecating `.rtp` stuff?
