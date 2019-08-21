{ nixpkgs ? import <nixpkgs> { }
}:
with nixpkgs.lib;
let
  getNvimSubmoduleDefs = options: options.sn.programs.neovim.definitions;
in
rec {
  # Builds a neovim module configuration, optionally merging in existing neovim
  # module config definitions from nixos, home-manager, and
  # home-manager-in-nixos.
  # NOTE: This may evaluate the current system's NixOS and/or home-manager
  # configurations, and if it does, it uses the nixpkgs and home-manager paths
  # that are given to it -- which may not necessarily be the ones used outside
  # of this.
  configuredNeovimModule =
    { pkgs ? nixpkgs, nvimConfig
    # These default to false because they are impure
    , withHMConfig ? false, withNixosConfig ? false, withNixosHMConfig ? false
    , hmPath ? <home-manager>, hmConfPath ? "", hmConfAttr ? ""
    }:
    # TODO figure out why this first assertion is failing even though I can
    # traceVal the asserted value and it is true...
    # assert !withHMConfig || (homeManagerNvimEnabled && !withNixosHMConfig);
    # assert !withNixosConfig || nixosNvimEnabled;
    # assert !withNixosHMConfig || (nixosHMSubmoduleNvimEnabled && !withHMConfig);
    let
      nixpkgsPath = pkgs.path;
      cfg = (evalModules {
        modules = [
          ({ ... }: { _module.args.pkgs = pkgs; })
          nvimConfig nvimModule
        ]
        ++ optionals (withHMConfig) (homeManagerNvimConfig { inherit hmPath hmConfPath hmConfAttr; })
        ++ optionals (withNixosConfig) (nixosNvimConfig { inherit nixpkgsPath; })
        ++ optionals (withNixosHMConfig) (nixosHMNvimConfig { inherit nixpkgsPath; })
        ;
      }).config;
    in cfg;

  homeManagerNvimEnabled = builtins.getEnv "HM_NVIM_ENABLED" == "true";
  nixosNvimEnabled = builtins.getEnv "NIXOS_NVIM_ENABLED" == "true";
  nixosHMSubmoduleNvimEnabled = builtins.getEnv "NIXOS_HM_NVIM_ENABLED" == "true";
  nixosConfigPath = let
    envPath = builtins.getEnv "NIXOS_CONFIG";
  in if envPath != "" then envPath else <nixos-config>;

  homeManagerNvimConfig = { hmPath, hmConfPath, hmConfAttr }: let
    hmNvimConfig = getNvimSubmoduleDefs (evalModules {
      modules = [ hmConfiguration ] ++ hmModules;
      specialArgs = {
        modulesPath = hmModulesPath;
      };
    }).options;

    hmConfiguration = let
      xdgHome = builtins.getEnv "XDG_CONFIG_HOME";
      envHome = builtins.getEnv "HOME";
      home = if xdgHome != "" then xdgHome else "${envHome}/.config";
    in
      if hmConfAttr == "" then
        if hmConfPath == "" then "${home}/nixpkgs/home.nix"
        else hmConfPath
      else (import hmConfPath).${hmConfAttr};

    hmModulesPath = "${hmPath}/modules/modules.nix";
    hmModules = import hmModulesPath {
      check = true;
      pkgs = nixpkgs;
      inherit (nixpkgs) lib;
    };
  in hmNvimConfig;

  # TODO use config path
  nixosNvimConfig = { nixpkgsPath ? pkgs.path, configPath ? nixosConfigPath }: let
    nixosNvimConf = getNvimSubmoduleDefs nixosEvaluated.options;
    nixosEvaluated = import "${nixpkgsPath}/nixos" { configuration = configPath; };
  in nixosNvimConf;

  nixosHMNvimConfig = { nixpkgsPath ? pkgs.path, configPath ? nixosConfigPath }: let
    nixosHMNvimConf = getNvimSubmoduleDefs nixosEvaluated.options.home-manager.users.${user};
    userHMConfs = filter
      (attrs: hasAttr user attrs && hasAttrByPath [ user "sn" "programs" "neovim" ] attrs)
      (nixosEvaluated.options.home-manager.users.definitions);
    nvimConfs = map (userConf: userConf.${user}.sn.programs.neovim) userHMConfs;
    nixosEvaluated = import "${nixpkgsPath}/nixos" {};

    user = builtins.getEnv "USER";
  in nvimConfs;

  nvimModule = import ./module.nix nixpkgs;


  # These are also imported by the module :)
  escapedName = name: replaceChars [ "/" "-" " " ] [ "-" "\\x2d" "\\x20" ] name;
  unescapedName = name: replaceChars [ "-" "\\x2d" "\\x20" ] [ "/" "-" " " ] name;
  # pinPathFor :: Either Path String -> String -> StorePath
  pinPathFor = directoryPath: pluginName: directoryPath + "/${escapedName pluginName}.json";
  pinFromPath = pinPath: let
    pinJson = builtins.fromJSON (builtins.readFile pinPath);
  in filterAttrs (n: _: elem n [ "url" "rev" "sha256" "version" "fetchType" ]) pinJson;
  fillPinsFromDir = { priority ? 100, directoryPath }: let
    pinFileNames = attrNames (
      filterAttrs (n: v: !elem v [ "directory" "unknown" ] && hasSuffix ".json" n)
      (builtins.readDir directoryPath)
    );
    namedPinFromFile = dir: fileName: let
      name = unescapedName (removeSuffix ".json" fileName);
      pin = mkOverride priority (pinFromPath (dir + "/${fileName}"));
    in nameValuePair name pin;
  in listToAttrs (map (namedPinFromFile directoryPath) pinFileNames);
}
