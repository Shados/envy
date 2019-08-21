{ nixpkgs ? import <nixpkgs> { }
, nvimConfigPath ? null
, withHMConfig ? false
, withNixosConfig ? false
, withNixosHMConfig ? false
}:
let
  nvimConfig = if nvimConfigPath != null then nvimConfigPath else {...}: {};
in
(import ./lib.nix { inherit nixpkgs; }).configuredNeovimModule {
  inherit nvimConfig withHMConfig withNixosConfig withNixosHMConfig;
}
