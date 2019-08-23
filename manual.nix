let
  nixpkgs = builtins.fetchGit {
    url = https://github.com/NixOS/nixpkgs;
    ref = "master";
    rev = "40235b78a201b97eb219d3a3b1c129b7ba5c30a7";
  };
  sn-config = builtins.fetchGit {
    url = https://github.com/Shados/nixos-config;
    ref = "master";
    rev = "36fc2cbcaf09643886dd79727f40467e122b112e";
  };
in
{
  # TODO pin to appropriate checkout?
  pkgs ? import nixpkgs {
    overlays = [
      (import "${sn-config}/overlays/lib/lua-overrides.nix")
      (import "${sn-config}/bespoke/pkgs/lua-packages/overlay.nix")
    ];
  }
}:
with pkgs;
with pkgs.lib;
let
  nvModule = import ./loaded-module.nix { nixpkgs = pkgs; };
  optionsFile = writeText "nv-options.json" nvModule.lib.optionsJSON;
  luaDeps = ps: with ps; [ inspect rapidjson lcmark ];
  luaPkg = luajit.withPackages luaDeps;
in
rec {
  html = runCommand "manual.html" rec {
    nativeBuildInputs = with luajitPackages; [
      gnumake
      moonscript
      mdbook
    ];
    inherit luaPkg optionsFile;
  }
  ''
    make book
    cp -r book $out
  '';
  shell = let
    fullDeps = html.nativeBuildInputs
      ++ (luaDeps luajitPackages);
  in mkShell {
    buildInputs = fullDeps;
    inherit optionsFile;
    shellHook = ''
      export LUA_PATH="$NIX_LUA_PATH"
      export LUA_CPATH="$NIX_LUA_CPATH"
    '';
  };
}
