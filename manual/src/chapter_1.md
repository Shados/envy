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

Or, if you've added envy as a flake input and have flake inputs available in your module arguments:
```nix
{ config, lib, inputs, pkgs, ... }:
{
  imports = [
    (envy.nixosModules.default { })
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
    (import "${envy}/home-manager.nix" { })
    ...
  ];
  ...
}
```

Or, if you've added envy as a flake input and have flake inputs available in your module arguments:
```nix
{ config, lib, inputs, pkgs, ... }:
{
  imports = [
    (envy.homeModules.default { })
    ...
  ];
  ...
}
```

## Standalone Setup
Usage as a standalone module is slightly more complicated, and is most easily
done by use of the `configuredNeovimModule` in Envy's `lib` module:
```nix
{ nixpkgs ? import <nixpkgs> { } }:
let
  envy = (builtins.fetchgit { url = https://github.com/Shados/envy; ref = "master"; });
  envyLib = (import "${envy}/lib.nix" { inherit nixpkgs; });
  envyModule = envyLib.configuredNeovimModule {
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
