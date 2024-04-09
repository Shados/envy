{ nixpkgs ? import <nixpkgs> { } }:
(import ./lib.nix { inherit nixpkgs; }).configuredNeovimModule {
  nvimConfig = {...}: {};
}
