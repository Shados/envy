# 1. Basic Usage
The main Envy module can basically be used in three different ways:
1) It can be used as a NixOS module, to configure neovim system-wide.
2) It can be used as a home-manager module, to configure neovim on a per-user
    basis.
3) It can be used standalone, e.g. in order to configure a custom neovim
   instance for a project's `shell.nix`.

In each of these uses, the module is configured in basically the same way, but
adding/accessing the module to begin with differs.


## Module Setup

Both the NixOS and home-manager modules expose the configuration interface
under `sn.programs.neovim` in NixOS; if you want to use a different
attribute path for it, take a look at the
`envy/nixos.nix`/`envy/home-manager.nix` source and manually do the same.

Both modules take an `enabled` argument, which defaults to `true`, rather than
exposing a `sn.programs.neovim.enable` option, due to a technical limitation.

### NixOS

Add the `envy/nixos.nix` module to `imports` in your `configuration.nix`:
```nix
{ config, lib, pkgs, ... }:
let
  envy = (builtins.fetchgit { url = https://github.com/Shados/envy; ref = "master"; });
in
{
  imports = [
    (import "${envy}/nixos.nix" { })
    ...
  ];
  ...
}
```

### home-manager
Add the `envy/home-manager.nix` module to `imports` in your `configuration.nix`:
```nix
{ config, lib, pkgs, ... }:
let
  envy = (builtins.fetchgit { url = https://github.com/Shados/envy; ref = "master"; });
in
{
  imports = [
    (import "${envy}/home-manager.nix" { mergeNixosDefinitions = false; })
    ...
  ];
  ...
}
```

`mergeNixosDefinitions` controls whether or not any `sn.programs.neovim`
settings from the current system's NixOS configuration should be merged into
the home-manager defintions. This allows for "layering" user-level neovim
configuration on top of the system-wide config. It is `false` by default.

NOTE: You are likely better off just directly including your NixOS
envy-configuration module in your hm config, if you want to layer the two, but
this approach is not always possible/viable.


## Standalone Setup
Usage as a standalone module is slightly more complicated, and is most easily
done by use of the `configuredNeovimModule` in Envy's `lib` module:
```nix
{ nixpkgs ? import <nixpkgs> { } }:
let
  envy = (builtins.fetchgit { url = https://github.com/Shados/envy; ref = "master"; });
  envyLib = (import "${envy}/lib.nix" { inherit nixpkgs; });
  envyModule = envyLib.configuredNeovimModule {
    # Whether or not to merge in Envy config pulled from the current NixOS Envy
    # module configuration
    withNixosConfig = false;
    # Whether or not to merge in Envy config pulled from the current
    # home-manager-in-NixOS Envy module configuration
    withNixosHMConfig = false;
    # Whether or not to merge in Envy config pulled from the current
    # home-manager Envy module configuration
    withHMConfig = false;
    nvimConfig = { config, lib, pkgs, ... }: {
      # Envy module config here
      pluginRegistry = {
        ...
      };
    };
  }
in
nixpkgs.mkShell {
  ...
  buildInputs = [
    envyModule.wrappedNeovim
    ...
  ];
}
```
