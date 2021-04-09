{ sources ? import ./nix/sources.nix }:
let
  nur-no-packages = import sources.nur { };
  pkgs = import sources.nixpkgs {
    overlays = with nur-no-packages.repos.shados.overlays; [
      lua-overrides
      lua-packages
    ];
  };
  inherit (pkgs) lib;
in
let
  nvModule = import ./loaded-module.nix { nixpkgs = pkgs; };
  optionsFile = pkgs.writeText "nv-options.json" nvModule.lib.optionsJSON;
  luaDeps = ps: with ps; [ inspect rapidjson lcmark ];
  luaPkg = pkgs.luajit.withPackages luaDeps;
  luaPkgs = luaPkg.pkgs;
in
rec {
  manual = pkgs.stdenv.mkDerivation {
    name = "envy-manual";
    src = ./.;
    nativeBuildInputs = with pkgs; [
      gnumake
      luaPkgs.moonscript
      mdbook
    ];
    inherit optionsFile;
    installPhase = ''
      cp -r docs $out
    '';
  };
  shell = pkgs.mkShell {
    nativeBuildInputs = manual.nativeBuildInputs ++ [
      luaPkg
      pkgs.niv
    ];
    inherit optionsFile;
    shellHook = ''
      export LUA_PATH="${luaPkgs.getLuaPath luaPkg}"
      export LUA_CPATH="${luaPkgs.getLuaCPath luaPkg}"
    '';
  };
}
