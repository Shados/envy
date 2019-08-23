# Introduction
Envy is a framework for Nix/Vim integration, providing:
- [x] A convenient way to pin and package Vim plugins as Nix derivations.
- [x] The ability for Vim plugin derivations to correctly depend on and pull in
  one another, and system dependencies (including plugin-native-language
  dependencies, C library dependencies, and executable dependencies).
- [x] A Nix-based configuration mechanism that allows individual plugin
  configuration to depend on the install-time state of other plugins,
  dependencies, and potentially the system (in NixOS).
- [x] A way to "layer" per-project plugins+configuration on top of per-user, in
  turn on top of per-system (albeit at a large memory cost at install-time).
- [x] A method for existing users of NixOS/home-manager to tightly integrate
  neovim configuration into it, meaning that aspects of their neovim
  configuration can reliably depend upon aspects of their system or user
  configuration.
- [x] More complexity than you want or need (probably).
- [ ] An end to world hunger.

The numbered chapters are intended to be read in order, as they build upon
information in earlier chapters. The appendices are intended more as reference
material.


## Why?
Mostly because neovim plugin configuration is a bit of a clusterfuck. There's a
deceptively (and increasingly) large amount of inherent complexity to the
problem space, because neo/vim plugins can have dependencies on many axes
(inter-plugin, external executable, Lua modules, remote host language modules,
etc.), and those in turn have their own dependency closures, and may also
depend on the system or user-level configuration.

Trying to reliably manage this cross-language, cross-system complexity using
*anything other than Nix* quickly descends into either A) madness, or B)
compromise. I'm not big on compromise.
