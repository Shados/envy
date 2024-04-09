{
  inputs.nixpkgs.url = "nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nur.url = "github:nix-community/NUR";

  outputs = { self, flake-utils, nixpkgs, nur }: flake-utils.lib.eachDefaultSystem (system: let
    nur-no-packages = import nur {
      nurpkgs = import nixpkgs { inherit system; };
    };
    pkgs = import nixpkgs {
      inherit system;
      overlays = with nur-no-packages.repos.shados.overlays; [
        lua-overrides
        lua-packages
      ];
      config.allowUnfree = true;
    };

    luaDeps = ps: with ps; [ inspect rapidjson lcmark ];
    luaPkg = pkgs.luajit.withPackages luaDeps;
    luaPkgs = luaPkg.pkgs;

    optionsFile = pkgs.writeText "nv-options.json" nvModule.lib.optionsJSON;
    nvModule = import ./loaded-module.nix { nixpkgs = pkgs; };
  in {
    devShell = pkgs.mkShell {
      nativeBuildInputs = self.packages.${system}.manual.nativeBuildInputs ++ [
        luaPkg
        pkgs.niv
      ];
      inherit optionsFile;
      shellHook = ''
        export LUA_PATH="${luaPkgs.getLuaPath luaPkg}"
        export LUA_CPATH="${luaPkgs.getLuaCPath luaPkg}"
      '';
    };
    packages.default = self.packages.${system}.manual;
    packages.manual = pkgs.stdenv.mkDerivation {
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
  }) // {
    homeModules.default = import ./home-manager.nix;
    nixosModules.default = import ./nixos.nix;
  };
}
