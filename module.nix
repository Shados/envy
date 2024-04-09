# We want to work as both a stand-alone module and a submodule, but submodules
# only get {config, lib, options} as arguments, so we have to wrap in another
# function to get pkgs
pkgs:
{ config, lib, options, ... }:
let
  inherit (lib) all any attrNames attrValues concatLists concatMap concatMapStringsSep concatStrings concatStringsSep elem escape filter filterAttrs filterAttrsRecursive flatten flip foldl' foldr getValues hasAttr hasPrefix isDerivation isFunction isList isString length literalExpression mapAttrs mapAttrsToList mkDefault mkIf mkOption mkOptionType nameValuePair optionals optionalAttrs optionalString recursiveUpdate replaceStrings singleton splitString types unique;
  inherit (builtins) unsafeDiscardStringContext;
  nvimLib = import ./lib.nix { nixpkgs = pkgs; };


  mkInitScript = isPluginOnly: plugList: ''
    -- Envy Lua runtime
    ${luaSetup}
  '' + optionalString (config.files != {} && !isPluginOnly) ''
    -- Locally-specified file tree, not a plugin per se
    ${addBeforeRtp (toString localNvimFiles)}
    ${optionalString (hasAfterDir localNvimFiles) (addAfterRtp (toString localNvimFiles))}
  '' + ''
    -- User-specified plugin loading
    ${luaLoadPlugins plugList (!isPluginOnly)}
    vim.api.nvim_command("filetype indent plugin on")
    vim.api.nvim_command("syntax on")

    -- User-provided config
  '' + optionalString (!isPluginOnly) ''
    ${vimUserConfig}
  '';

  vimUserConfig = let
    vimText = ''
      " Envy: prePluginConfig
      ${optionalString (config.prePluginConfig != null) config.prePluginConfig}
      " Envy: per-plugin extraConfig
      ${perPluginExtraConfig}
      " Envy: extraConfig
      ${config.extraConfig}
    '';
    luaText = ''
      -- Envy: prePluginConfig
      ${optionalString (config.prePluginConfig != null) config.prePluginConfig}
      -- Envy: per-plugin extraConfig
      ${perPluginExtraConfig}
      -- Envy: extraConfig
      ${config.extraConfig}
    '';
    langSwitch = {
      vimscript = ''vim.api.nvim_command("source ${pkgs.writeText "user-config.vim" vimText}")'';
      lua = luaText;
      moonscript = compileMoon (luaText +
        # Suppress a MoonScript-generated return value (it does this due to being an expression-oriented language)
        ''
          return
        '');
    };
  in langSwitch.${config.configLanguage};

  initScript = mkInitScript false plugList;
  # This is used for declaratively generating the remote plugins manifest
  pluginOnlyInitScript = mkInitScript true plugList;

  # localNvimFiles: A symlink tree of the configured extra nvim runtime files {{{
  localNvimFiles = flip pkgs.callPackage {
    # NOTE: Not sure why I have to manually specify this, despite feeding it
    # into `nativeBuildInputs` I don't get the correct package variant spliced
    # in without being explicit.
    lua = pkgs.pkgsBuildHost.luajit;
  } (
    { runCommand, writeText
    , lua
    }:
    let
      filesJson = let
        fileList = mapAttrsToList (addPath) (filterAttrs (n: v: v.enable) config.files);
        # addPath :: String -> NvimFile -> { source :: String, target :: String }
        addPath = name: file: {
          inherit (file) source target;
        };
      in writeText "local-nvim-files.json" (builtins.toJSON fileList);

      # We already need Lua due to nvim, and the other deps are pretty minimal --
      # doing this in bash would be less nice, jq isn't that great for working
      # with collections.
      luaDeps = ps: with ps; [ inspect luafilesystem rapidjson ];
      luaBuilder = ./lua/config-nvim-builder.lua;
    in
    runCommand "config-nvim" {
      nativeBuildInputs = [
        # TODO change this when adding an option to configure the lua package
        # used for neovim? would just be to save on having duplicate Lua's
        # installed in this case; this one shouldn't particularly be open to
        # customisation
        (lua.withPackages luaDeps)
      ];
    } ''
      lua ${luaBuilder} ${filesJson} $out
    '');
  # }}}

  luaSetup = builtins.readFile ./lua/vimrc-setup.lua;

  luaLoadPlugins = plugList: lazyOk: let
    luaLoadPluginsSrc = concatStrings luaLoadPluginsLines;
    luaLoadPluginsLines =
      (flip map beforePlugList (plugin: conditionalWrapper plugin "${(addBeforeRtp (plugPath plugin))}\n")) ++
      (flip map afterPlugList (plugin: conditionalWrapper plugin "${(addAfterRtp (plugPath plugin))}\n")) ++
      (flip map localPlugList (plugin: conditionalWrapper plugin ''
        if envy.dir_exists(${toLuaString "${plugPath plugin}/after"}) then
          ${addAfterRtp (plugPath plugin)}
        end
      '')) ++
      optionals lazyOk (flatten (flip map lazyPlugList (plugin:
        optionals (strListSet plugin.for) (flip map (ensureList plugin.for) (ft: ''
          table.insert(envy.lazy_filetype_plugins[${toLuaString ft}], ${toLuaString (plugPath plugin)})
        '')) ++
        optionals (strListSet plugin.on_cmd) (flip map (ensureList plugin.on_cmd) (cmd: ''
          table.insert(envy.lazy_command_plugins[${toLuaString cmd}], ${toLuaString (plugPath plugin)})
        '')) ++
        optionals (strListSet plugin.on_map) (flip map (ensureList plugin.on_map) (mapping: ''
          table.insert(envy.lazy_mapped_plugins[${toLuaString mapping}], ${toLuaString (plugPath plugin)})
        ''))
      ))) ++ singleton ''
        envy.set_rtp()
        envy.setup_lazy_loading()
      '';

    baseList = if lazyOk
      then filter (plug: !(isLazyPlugin plug)) plugList
      else plugList;
    lazyPlugList = filter (isLazyPlugin) plugList;
    beforePlugList = baseList;
    afterPlugList = flip filter baseList
      (plugin: !isLocal plugin && hasAfterDir plugin.source.outPath);
    localPlugList = filter (isLocal) baseList;

    conditionalWrapper = plugin: lines: let
      condExprs = {
        vimscript = cond: ''
          if vim.api.nvim_eval(${toLuaString cond}) ~= 0" then
            ${lines}
          end
        '';
        lua = cond: ''
          local cond_expr = function()
            ${cond}
          end
          if cond_expr() then
            ${lines}
          end
        '';
        # moonc will generate the 'return' for the below function
        moonscript = cond: condExprs.lua (compileMoon cond);
      };
    in if plugin.condition != null
      then condExprs.${config.configLanguage} plugin.condition
      else lines;
    ensureList = maybeList: if isList maybeList then maybeList else singleton maybeList;
    plugPath = plugin: if isLocal plugin then plugin.dir else plugin.source.outPath;
    isLocal = plugin: plugin.pluginType == "local";
    isLazyPlugin = plugin: strListSet plugin.for || strListSet plugin.on_cmd || strListSet plugin.on_map;
  in luaLoadPluginsSrc;

  perPluginExtraConfig = let
    matchingPlugins = filter (plugin: plugin.extraConfig != null) sortedPlugins;
  in concatMapStringsSep "\n\n" (plugin: plugin.extraConfig) matchingPlugins;

  # mergedBuckets: List of buckets with merged plugin directories (where possible) {{{
  mergedBuckets = let
    # mergeBucket :: [Plugin] -> [Either PluginDrv MergedPluginDrv]
    mergeBucket = bucket: let
      soloPlugins = filter (p: !isMergeablePlugin p) bucket;
      # isMergeablePlugin :: PluginDrv -> Bool
      isMergeablePlugin = plugin: !(
        # Any of these should prevent a plugin from being merged
           !plugin.mergeable
        || strListSet plugin.on_cmd
        || strListSet plugin.on_map
        || strListSet plugin.for
        || plugin.condition != null
        || plugin.pluginType == "local"
      );
      mergeablePlugins = filter (isMergeablePlugin) bucket;
      # Theoretically, could merge plugins in the same bucket with the same
      # "for", but probably not worthwhile
      mergedPlugin = let
        drv = pkgs.symlinkJoin {
          name = "merged-vim-plugins";
          paths = map (plugin: plugin.source.outPath) mergeablePlugins;
          nativeBuildInputs = [
            config.neovimPackage
          ];
          postBuild = ''
            # Rebuild help tag index
            if [ -d "$out/doc" ]; then
              if [ -e "$out/doc/tags" ]; then
                echo "Removing linked help tags"
                rm -f "$out/doc/tags"
              fi
              echo "Building help tags for merged plugins"
              if ! nvim -N -u NONE -i NONE -n -E -s -V1 -c "helptags $out/doc" +quit!; then
                echo "Failed to build help tags!"
                exit 1
              fi
            else
              echo "No docs available"
            fi
          '';
        };
      in {
        source = drv;
        pluginType = "path";
        condition = null; on_cmd = []; on_map = []; for = [];
      };
      mergedList =
        if length mergeablePlugins > 1
          then [ mergedPlugin ]
          else if length mergeablePlugins == 0 then []
        else mergeablePlugins;
    in soloPlugins ++ mergedList;
  in map (mergeBucket) rawPluginBuckets;
  # }}}

  # rawPluginBuckets: List of required plugin "buckets"... {{{
  # Each bucket is a list of plugins whose dependencies are satisfied by the
  # plugins in all previous buckets; essentially each bucket contains plugins
  # that should be loaded *after* one or more plugins in one or more of the
  # previous buckets, but that have no specific ordering requirements with
  # respect to the other plugins in their own bucket.

  # This is used both to created a list of plugins sorted in a valid load
  # order, and optionally also to generate "merged" plugins (where possible) in
  # order to minimize the number of directories added to nvim's runtimepath.
  rawPluginBuckets = map (bucket: map (path: registryByPath.${path}) bucket) rawStringPluginBuckets;
  rawStringPluginBuckets = let
    # addToBuckets :: [String] -> [[PluginDrv]] -> [String] -> [[PluginDrv]]
    addToBuckets = done: buckets: rem: let
      buckets' = buckets ++ [ currentBucket ];
      # List of plugins whose dependencies (soft and hard) are satisfied by the
      # plugins already done
      currentBucket = filter (p: isSatisfied p) rem;
      isSatisfied = path: let
        # Set of plugins that this plugin must be ordered after, and that are
        # part of the plugin dependency closure of this neovim config
        after = filter (n: elem n requiredPlugins) depIndex.${path}.after;
      in all (dep: elem dep done) after;

      rem' = filter (p: ! isSatisfied p) rem;
      done' = done ++ currentBucket;
    in if length rem' > 0
      then addToBuckets done' buckets' rem'
      else buckets';
  in addToBuckets [] [] requiredPlugins;
  # }}}

  # depIndex: Maps plugin paths to the plugins that should be loaded before/after them {{{
  depIndex = let
    fullIndex = foldl' (addDepInfo) {} (mapAttrsToList (nameValuePair) registryByPath);
    # addDepInfo :: { Plugin } -> {name :: String, value :: Plugin } ->
    #   { Plugin }
    addDepInfo = index: {name, value}: let
      spec = value;

      updatedIndex = foldl' (addUpdate) index updates;

      # addUpdate :: { Plugin } ->
      #   {name :: String, value :: { Before = [String]; After = [String] } ->
      #   { Plugin }
      addUpdate = index: {name, value}: let
        existing = index.${name} or {};
      in index // {
        ${name} = {
          after = existing.after or [] ++ value.after or [];
          before = existing.before or [] ++ value.before or [];
        };
      };

      updates = beforeUpdates ++ afterUpdates;

      beforeUpdates =
        map (plugName: nameValuePair plugName { before = [ name ]; }) (deps ++ spec.after or [])
        ++ singleton (nameValuePair name { before = spec.before or []; });

      afterUpdates =
        (map (plugName: nameValuePair plugName { after = [ name ]; }) (spec.before or []))
        ++ singleton (nameValuePair name { after = spec.after or [] ++ deps;});

      deps = spec.dependencies or [];
    in updatedIndex;
  in fullIndex;
  # }}}

  plugList = if config.mergePlugins then flatten mergedBuckets else sortedPlugins;

  # sortedPlugins: List of required plugin drvs sorted into valid loading order
  sortedPlugins = flatten rawPluginBuckets;
  # }}}

  # requiredPlugins: Dependency closure of raw plugins that need to be installed
  requiredPlugins = let
    getDeps = pluginPath: let
      directDeps = registryByPath.${pluginPath}.dependencies;
    in [ pluginPath ] ++ concatLists (map getDeps directDeps);
  in unique (concatLists (map getDeps (enabledPlugins)));

  # Directly enabled plugins, not including dependencies
  enabledPlugins = attrNames (filterAttrs (n: v: v.enable) registryByPath);

  registryByPath = let
    # Map output paths to plugin-specs, including dependencies, generating new
    # ones for derivation dependencies that aren't already in the registry
    registry = foldl' (registry: spec: let
      # Only 'local' plugins won't have an outPath, at this point
      path = pathFromSpec spec;

      registryWithDeps = if spec ? source
        then let
          registryWithDrvDeps = registerDeps registry spec.source;
        in foldl' (registry': drv: registerDep registry' drv) registryWithDrvDeps (filter isDerivation spec.dependencies)
        else registry;

      registerDeps = registry: drv: let
        deps = drv.dependencies or [];
      in foldl' (registerDep) registry deps;

      registerDep = registry': dep: recursiveUpdate {
        ${unsafeDiscardStringContext dep.outPath} = wrapUpstreamPluginDrv dep true;
      } (registerDeps registry' dep);

    in registryWithDeps // {
      ${path} = spec;
    }) {} (attrValues drvRegistry);

    # Ensure all dependency and ordering references are by derivation, not by name
    registry' = mapAttrs (path: spec: spec // {
      dependencies = (mapDepsToPaths spec.dependencies) ++ getDrvDeps spec;
      after = mapDepsToPaths (spec.after or []);
      before = mapDepsToPaths (spec.before or []);
    }) registry;

    mapDepsToPaths = deps: map depToPath deps;
    depToPath = dep:
      if builtins.isString dep then
        if hasAttr dep drvRegistry
        then pathFromSpec drvRegistry.${dep}
        else throw "Dependency `${dep}` does not exist in `sn.programs.neovim.pluginRegistry`"
      else unsafeDiscardStringContext dep.outPath;
    pathFromSpec = spec:
      if spec.pluginType == "local" then spec.dir
      else if spec.pluginType == "path" then unsafeDiscardStringContext spec.source
      else unsafeDiscardStringContext spec.source.outPath;
  in registry';

  getDrvDeps = spec: let
    deps = if spec ? source && isDerivation spec.source
      then spec.source.dependencies or []
      else [];
  in map (d: unsafeDiscardStringContext d.outPath) deps;

  # drvRegistry: pluginRegistry where all non-local plugins are ensured to have proper drv sources {{{
  drvRegistry = let
    composePlugin = pluginName: plugin: plugin // {
      source = if plugin.pluginType == "path"
      then if plugin.source != null
        then buildPluginFromPath pluginName plugin
        else throw "Neither `source` nor `dir` specified for `sn.programs.neovim.pluginRegistry.${pluginName}`"
      else plugin.source;
    };
  in mapAttrs (composePlugin) taggedPluginRegistry;
  # }}}

  # taggedPluginRegistry: pluginRegistry with source-type tagging {{{
  taggedPluginRegistry = let
    # amendPluginRegistration :: String -> Plugin -> TaggedPlugin
    amendPluginRegistration = name: plugin:
      if plugin.dir != null
        then  plugin // { pluginType = "local"; }

      else if plugin ? source && isDerivation plugin.source
        then  plugin // { pluginType = "upstream"; }

      else    plugin // { pluginType = "path"; };
  in mapAttrs (amendPluginRegistration) config.pluginRegistry;
  # }}}

  # Helpers {{{
  # TODO: Is there anything else we can automatically infer?
  # wrapUpstreamPluginDrv :: String -> Derivation -> Plugin
  wrapUpstreamPluginDrv = pluginDrv: includeEnable: {
    source = pluginDrv;
    remote = {}
      # NOTE python3 is behind optionalAttrs as we don't want the user to have
      # to mkForce in order to fix a false-negative
      // optionalAttrs (pluginDrv ? python3Dependencies) {
        python3 = true;
        python3Deps = pluginDrv.python3Dependencies;
      };
    dependencies = []; # Will be populated later
    binDeps = pluginDrv.propagatedBuildInputs or [];
    mergeable = true;
    condition = null; on_cmd = []; on_map = []; for = [];
    extraConfig = null;
    pluginType = "upstream";
  } // optionalAttrs includeEnable { enable = false; };

  # buildPluginFromPath :: String -> Plugin -> PluginDrv
  buildPluginFromPath = pluginName: spec: let
    pname = pluginName;
    version = "frompath";
    src = spec.source;
  in pkgs.vimUtils.buildVimPlugin (rec {
    inherit pname version src;
    name = "${pname}-${version}";
  });

  # sourceFromPin :: {SourcePin} -> StorePath
  sourceFromPin = pin: pkgs.fetchgit { inherit (pin) url rev sha256 leaveDotGit fetchSubmodules; };

  # getRemoteDeps :: String -> Any (Bool ExtraPython3Package ExtraPython3Package)
  getRemoteDeps = attrname: map (plugin: plugin.remote.${attrname});
  # plugDepAsString :: Either String Derivation -> String
  plugDepAsString = dep: if isString dep then dep else dep.pname or dep.name;
  # buildPythonEnv :: String -> { Derivation } ->
  #   Either ExtraPython3Package ExtraPython3Package -> Derivation
  buildPythonEnv = vimDepName: pyPackages: extraPackages: let
    pluginPythonPackages = getRemoteDeps vimDepName (filter (plugin: hasAttr vimDepName plugin.remote) sortedPlugins);
  in pyPackages.python.withPackages (ps:
      [ ps.pynvim ]
      ++ (extraPackages ps)
      ++ (concatMap (f: f ps) pluginPythonPackages)
    );

  # requiresRemoteHost :: String -> Bool
  requiresRemoteHost = remoteHost: any (plugin: let
    in plugin.remote.${remoteHost} or false == true) sortedPlugins;

  # mkLangPackagesOption :: String -> a -> String -> Option
  mkLangPackagesOption = lang: langPackageType: examplePackages: mkOption {
    description = ''
      A function that takes an attribute set of ${lang} packages (typically
      passed from nixpkgs) and returns a list of ${lang} packages that this
      plugin depends on.
    '';
    type = langPackageType;
    default = (_: []);
    defaultText = "packageSet: []";
    example = literalExpression "(packageSet: with packageSet: [ ${examplePackages} ])";
  };

  # mkRemoteHostOption :: String -> Option
  mkRemoteHostOption = lang: mkOption {
    description = ''
      Whether or not this plugin requires the remote plugin host for ${lang}.

      Will effectively be set to true if any ${lang} package dependencies are
      specified for this plugin.
    '';
    type = with types; bool;
    default = false;
  };

  compileMoon = let
    moonFile = moontext: pkgs.runCommand "compiled.lua" {
      preferLocalBuild = true;
      src = pkgs.writeText "src.moon" moontext;
      nativeBuildInputs = [
        pkgs.luajitPackages.moonscript
      ];
    } ''
      moonc -o $out $src
    '';
  in t: builtins.readFile (moonFile t);

  # strListSet :: Either String [String] -> Bool
  strListSet = strList: if isList strList then length strList > 0 else true;

  toLuaString = str: "'${escape [ "'" "\\" ] str}'";

  escapePlugPath = path: escape [ "," "\\" ] path;

  hasAfterDir = path: let
    dirSet = builtins.readDir path;
  in (dirSet ? "after" && dirSet.after == "directory");

  addBeforeRtp = path: "envy.before_rtp = envy.before_rtp .. ${toLuaString ",${escapePlugPath (path)}"}";
  addAfterRtp = path: "envy.after_rtp = ${toLuaString ",${escapePlugPath (path)}/after"} .. envy.after_rtp";
  # }}}

  # Types / submodules {{{
  mkLangPackagesType = langName: pkgCond: mkOptionType {
    name = "extra-${langName}-packages";
    description = "${langName} packages in `${langName}.withPackages` format";
    check = with types; val: isFunction val && pkgCond val;
    merge = langPackagesMergeFunc;
  };
  extraPython3PackageType = mkLangPackagesType
    "python3"
    (val: isList (val pkgs.python3Packages));
  extraLuaPackageType = mkLangPackagesType
    "lua"
    (val: true);
  # langPackagesMergeFunc :: Any -> [({Derivation} -> [Derivation])] ->
  #   ({Derivation} -> [Derivation])
  langPackagesMergeFunc = loc: defs:
    packageSet: foldr (a: b: a ++ b) [] (map (f: f packageSet) (getValues defs));

  nvimFile = { name, config, ... }: {
    options = {
      enable = mkOption {
        type = with types; bool;
        default = true;
        description = ''
          Whether or not this neovim file should be generated. This option
          allows specific files to be disabled.
        '';
      };
      target = mkOption {
        type = with types; str;
        description = ''
          Name of the symlink, relative to the folder added to the neovim
          runtimepath. Defaults to the attribute name.
        '';
      };
      text = mkOption {
        type = with types; nullOr lines;
        default = null;
        description = ''
          Literal text of the file. Used to generate a file to set the source
          option.
        '';
      };
      source = mkOption {
        type = with types; path;
        description = ''
          Path to the file or directory to symlink in.

          If the source is a directory, a directory with a corresponding name
          will be created in the folder added to the neovim runtimepath, with
          symlinks to files in the source directory, and same the treatment
          applied recursively for child directories.

          Overrides the text option if both are set.
        '';
      };
    };
    config = {
      target = mkDefault name;
      source = mkIf (config.text != null) (
        let name' = "config-nvim-${replaceStrings [ " " ] [ "_" ] (baseNameOf name)}";
        in mkDefault (pkgs.writeText name' config.text)
      );
    };
  };

  pluginConfigType.options = {
    enable = mkOption {
      description = ''
        Whether or not this neovim plugin should be installed and used.
      '';
      type = with types; bool;
      default = false;
    };
    dependencies = mkOption {
      # TODO change things like `vimPlugins` to be within-manual references?
      description = ''
        List of other vim plugins that are dependencies of this plugin.

        Items can either be existing vim plugin derivations, or strings
        corresponding to `pluginRegistry` attributes.
      '';
      type = with types; listOf (either str package);
      default = [];
    };
    before = mkOption {
      description = ''
        List of other vim plugins that this plugin should be loaded *before*.

        This can be seen as a "soft" form of making this plugin a dependency of
        each of the listed plugins.

        Items can either be existing vim plugin derivations, or strings
        corresponding to `pluginRegistry` attributes.
      '';
      type = with types; listOf str;
      default = [];
    };
    after = mkOption {
      description = ''
        List of other vim plugins that this plugin should be loaded *after*.

        This can be seen as a "soft" form of making each of the listed plugins
        dependencies of this plugin.

        Items can either be existing vim plugin derivations, or strings
        corresponding to `pluginRegistry` attributes.
      '';
      type = with types; listOf str;
      default = [];
    };
    binDeps = mkOption {
      description = ''
        A list of derivations containing executables that need to be available
        in the `$PATH` of the neovim process for this plugin to use.
      '';
      type = with types; listOf package;
      default = [];
    };
    luaDeps = mkLangPackagesOption "Lua" extraLuaPackageType "luafilesystem";
    remote =  {
      python3 = mkRemoteHostOption "Python 3";
      python3Deps = mkLangPackagesOption "Python 3" extraPython3PackageType "python-language-server";
    };
    condition = mkOption {
      description = ''
        A VimL expression that will be evaluated to determine whether or not
        to execute the vim-plug 'Plug' command for this plugin (which will
        typically load the plugin, or configure it to be lazily loaded).

        Leave null in order to unconditionally always run the 'Plug' command
        for this plugin.
      '';
      type = with types; nullOr str;
      default = null;
    };
    extraConfig = mkOption {
      description = ''
        Extra lines of `init.vim` configuration associated with this plugin,
        that need to be executed after the plugin loading.

        Leave null if no such extra configuration is required.
      '';
      type = with types; nullOr lines;
      default = null;
    };

    mergeable = mkOption {
      description = ''
        Whether or not it is safe to merge this plugin with others in the same
        bucket in the load order.
      '';
      type = with types; bool;
      default = true;
    };

    source = mkOption {
      description = ''
        Source of the vim plugin.

        Set to an existing vim plugin derivation, or to a Nix store path to
        build a vim plugin derivation from. Otherwise, leave this as `null` and
        set the `dir` configuration option for this plugin instead.
      '';
      default = null;
      type = with types; nullOr (either path (either package str));
    };
    # TODO replace this by just handling non-Nix-store paths in source, maybe?
    dir = mkOption {
      description = ''
        If set, specifies a directory path that the plugin should be loaded
        from at neovim run-time, avoiding the use of a Nix-provided plugin
        directory.

        Relative paths will be relative to the generated `init.vim`, which is
        in the Nix store. As the value is passed into a '-quoted VimL string,
        it is possible to escape this to use a relative path, e.g.:

        ```nix
        ' . $HOME. '/.config/vim/local/some-plugin
        ```

        If this is set, `source` will not be used.
      '';
      type = with types; nullOr str;
      default = null;
    };
    rtp = mkOption {
      description = ''
        Subdirectory of the plugin source that contains the Vim plugin.

        Leave as `null` to simply use the root of the source.
      '';
      type = with types; nullOr str;
      default = null;
    };
    on_cmd = mkOption {
      description = ''
        One or more commands that should trigger on-demand/lazy loading of this
        plugin.

        Can be specified with either a single string or list of strings.

        NOTE: Lazy-loading functionality will likely conflict with the use of
        any additional, non-Envy plugin manager.
      '';
      # TODO type-check, must start with uppercase
      type = with types; either str (listOf str);
      default = [];
    };
    on_map = mkOption {
      description = ''
        One or more &lt;Plug&gt;-mappings that should trigger on-demand/lazy
        loading of this plugin.

        Can be specified with either a single string or list of strings.

        NOTE: Lazy-loading functionality will likely conflict with the use of
        any additional, non-Envy plugin manager.
      '';
      # TODO type-check, must start <Plug>? or elide <Plug>?
      type = with types; either str (listOf str);
      default = [];
    };
    for = mkOption {
      description = ''
        One or more filetypes that should trigger on-demand/lazy loading of
        this plugin.

        Can be specified with either a single string or list of strings.

        NOTE: Lazy-loading functionality will likely conflict with the use of
        any additional, non-Envy plugin manager.
      '';
      type = with types; either str (listOf str);
      default = [];
    };
  };
  # }}}
in
{
  # Workaround to provide proper option value definition location information.
  # Because this module is intended for possible use as a submodule, it can
  # only take { name, config, lib, options } as module arguments.
  # But we also need pkgs, so we have to wrap in a containing function to pass
  # that in, which unfortunately appears to break the method the module system
  # uses to track location information.
  _file = builtins.toString ./module.nix;

  options = {
    # Public interface {{{
    neovimPackage = mkOption {
      type = with types; package;
      description = ''
        The base neovim package to wrap.
      '';
      default = pkgs.neovim-unwrapped;
      defaultText = "pkgs.neovim-unwrapped";
    };
    # For managing vim plugins and associated init.vim configuration fragments;
    # this option is the primary interface to configure neovim via this module.
    pluginRegistry = mkOption {
      type = with types; attrsOf (submodule pluginConfigType);
      description = ''
        An attribute set describing the available/known neovim plugins.
      '';
      default = {};
      # TODO: Load this from a CI-tested example file?
      example = literalExpression ''
        (let
          inherit (pkgs) vimPlugins;
          pins = import ./niv/sources.nix { };
        in {
          nvim-moonmaker = {
            enable = true;
            # Build plugin derivation from a Niv source pins attribute set
            source = config.sn.programs.neovim.lib.buildVimPluginFromNiv pins "nvim-moonmaker";
            # Decide whether or not to load at run-time based on the result of
            # a VimL expression
            condition = "executable('moonc')";
          };

          vim-auto-save = {
            enable = true;
            source = vimPlugins.vim-auto-save;
            # Lazily load on opening a tex file
            for = "tex";
          };

          nerdtree = {
            enable = true;
            source = vimPlugins.nerdtree;
            # Lazily load on command usage
            on_cmd = "NERDTreeToggle";
            extraConfig = '''
              " Prettify NERDTree
              let NERDTreeMinimalUI = 1
              let NERDTreeDirArrows = 1
            ''';
          };

          # A "path" plugin built from a source path
          "nginx.vim" = {
            enable = true;
            source = ../nvim-files/local/nginx;
          };

          # A "local" plugin not directly managed by Nix, merely loaded at nvim
          # run-time from the specified directory
          "devplugin" = {
            enable = true;
            dir = "/home/shados/projects/vim/devplugin";
          };

          # A plugin configured but not enabled
          vim-devicons = {
            source = vimPlugins.vim-devicons;
            # vim-devicons needs to be loaded after these plugins, if they
            # are being used, as per its installation guide
            after = [
              "nerdtree" "vim-airline" "ctrlp-vim" "powerline/powerline"
              "denite-nvim" "unite-vim" "lightline-vim" "vim-startify"
              "vimfiler" "vim-flagship"
            ];
          };
        })
      '';
    };

    mergePlugins = mkOption {
      type = with types; bool;
      default = false;
      description = ''
        Whether or not to collect plugins into "buckets" based upon their
        position in the load order, and then merge those which can be merged,
        in order to minimise the number of directories added to vim's
        `runtimepath`, decreasing startup time.
      '';
    };

    # TODO, X->Lua compiler options
    # TODO, validity check on the produced vimscript/lua file
    configLanguage = mkOption {
      type = with types; enum [ "vimscript" "lua" "moonscript" ];
      default = "vimscript";
      description = ''
        The language you wish to use for user-supplied configuration line
        options (`extraConfig`, `prePluginConfig`, and
        `pluginRegistry.<pluginName>.extraConfig`).
      '';
    };

    # For managing non-plugin-related init.vim configuration fragments
    extraConfig = mkOption {
      type = with types; lines;
      default = "";
      description = ''
        Extra lines of `init.vim` configuration to append to the generated
        ones, immediately following any `pluginRegistry.<pluginName>.extraConfig`
        config lines.
      '';
    };
    prePluginConfig = mkOption {
      description = ''
        Extra lines of `init.vim` configuration to append to the generated
        ones, immediately prior to any `pluginRegistry.<pluginName>.extraConfig`
        config lines.

        Leave null if no such extra configuration is required.
      '';
      type = with types; nullOr lines;
      default = null;
    };

    # For managing what would typically be locally managed folders and files in
    # the .config/nvim folder; these options essentially create a vim vim
    # plugin that is explicitly added to the runtimepath.
    # NOTE: We could limit the list of directories to just the ones that are
    # actually searched for runtime files, but being prescriptive here seems
    # pointless.
    files = mkOption {
      type = with types; attrsOf (submodule nvimFile);
      default = {};
      description = ''
        Files and folders to link into a folder in the runtimepath; outside of
        Envy these would typically be locally-managed files in the
        `~/.config/nvim` folder.
      '';
      example = literalExpression ''
        {
          autoload.source = ./neovim/autoload;
          ftplugin.source = ./neovim/ftplugin;
          "neosnippets/nix.snip".text = '''
            snippet nxo
            abbr    NixOS Module Option
            	mkOption {
            		type = with types; '''''${1:str};
            		default = "'''''${2}";
            		description = '''
            		  '''''${3}
            		''';
            		example = "'''''${4}'''''${0}";
            	};
          ''';
        }
      '';
    };

    # Language-specific package options
    withPython3 = mkOption {
      type = types.bool;
      default = requiresRemoteHost "python3";
      description = ''
        Enable Python 3 provider. Set to `true` to use Python 3 plugins.
      '';
    };
    extraPython3Packages = mkOption {
      type = extraPython3PackageType;
      default = (_: []);
      defaultText = "ps: []";
      example = literalExpression "(ps: with ps; [ python-language-server ])";
      description = ''
        A function in `python.withPackages` format, which returns a list of
        Python 3 packages required for your plugins to work.

        Using the per-plugin `python3Deps` is strongly preferred; this should
        only be necessary if you need some Python 3 packages made available to
        neovim for a plugin that is *not* being managed by this module.
      '';
    };

    # Generic package options
    extraBinPackages = mkOption {
      type = with types; listOf package;
      default = [];
      description = ''
        A list of derivations containing executables that need to be available
        in the `$PATH` of the neovim process for this plugin to use.

        Using the per-plugin `binDeps` is generally preferred; this should only
        be necessary if you need to make executables available for either:
        - A plugin that is *not* being managed by this module.
        - A binding or function in your `init.vim`, or other direct use from
          within neovim.
      '';
    };
    # }}}

    # Read-only public interface {{{
    lib = mkOption {
      type = with types; attrs;
      readOnly = true;
      description = ''
        Library of utility functions.
      '';
    };
    # }}}

    # Internal, read-only options {{{
    # These are basically implementation details of the module.
    depIndexJson = mkOption {
      type = with types; path;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Path to JSON file mapping plugin names to the plugins that should be
        loaded before/after them.
      '';
    };
    neovimRC = mkOption {
      type = with types; path;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        The contents of the `init.vim` file, generated by the other
        configuration options in this module.
      '';
    };
    pluginOnlyRC = mkOption {
      type = with types; path;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Minimal version of the generated `init.vim` file, used by the neovim
        wrapper to generate the remote plugin manifest.
      '';
    };
    python3Env = mkOption {
      type = with types; nullOr package;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Generated Python 3 environment containing the plugin host package, the
        required per-plugin Python 2 depenedencies, and the specified
        `extraPython3Packages`.
      '';
    };
    luaModules = mkOption {
      type = with types; listOf extraLuaPackageType;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Generated list of Lua packages (in `lua.withPackages()` format) that
        should be made available to the neovim process.
      '';
    };
    binDeps = mkOption {
      type = with types; listOf package;
      default = [];
      internal = true;
      visible = false;
      description = ''
        Generated list of derivations containing executables that should be
        made available to the neovim process.
      '';
    };
    generatePluginManifest = mkOption {
      type = with types; bool;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Whether or not a remote host plugin manifest needs to be generated.
      '';
    };
    wrappedNeovim = mkOption {
      type = with types; package;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        The configured, wrapped neovim and plugins.
      '';
    };
    debug = mkOption {
      type = with types; attrs;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Attribute set of developer debugging values.
      '';
    };
    # }}}
  };

  config = {
    # Setting read-only options
    neovimRC = pkgs.writeText "init.lua" initScript;
    pluginOnlyRC = pkgs.writeText "plugin-only-init.lua" pluginOnlyInitScript;
    depIndexJson = pkgs.writeText "nvim-dependency-index.json" (builtins.toJSON (depIndex));
    python3Env = buildPythonEnv "python3Deps" pkgs.python3Packages config.extraPython3Packages;
    luaModules = concatMap (plugin: singleton plugin.luaDeps) (filter (plugin: plugin ? luaDeps) sortedPlugins);
    binDeps = concatMap (plugin: plugin.binDeps) sortedPlugins;
    wrappedNeovim = let
      configureNeovim = pkgs.callPackage ./wrapper.nix {
        neovim-unwrapped = config.neovimPackage;
      };
    in configureNeovim config;
    generatePluginManifest = any (v: v) (map (requiresRemoteHost) [ "python3" ]);

    lib = {
      inherit (nvimLib) buildVimPluginFromNiv;
      inherit buildPluginFromPath compileMoon;

      optionsJSON = let
        # Based on home-manager's manual/options JSON generation, which is
        # based on nixpkgs
        # Customly sort option list for the man page.
        # TODO add a machine-readable 'Type' representation so I can do
        # per-option-type markdown more easily
        optionsList = lib.sort optionLess optionsListDesc;
        # Custom "less" that pushes up all the things ending in ".enable*"
        # and ".package*"
        optionLess = a: b:
          let
            ise = lib.hasPrefix "enable";
            isp = lib.hasPrefix "package";
            cmp = lib.splitByAndCompare ise lib.compare
                                       (lib.splitByAndCompare isp lib.compare lib.compare);
          in lib.compareLists cmp a.loc b.loc < 0;
        optionsListDesc = lib.flip map (lib.optionAttrSetToDocList options) (opt: opt // {
            # Clean up declaration sites to not refer to the NixOS source tree.
            declarations = map stripAnyPrefixes opt.declarations;
          }
          // lib.optionalAttrs (opt ? example) { example = substFunction opt.example; }
          // lib.optionalAttrs (opt ? default) { default = substFunction opt.default; }
          // lib.optionalAttrs (opt ? type) { type = substFunction opt.type; }
          );
        # We need to strip references to /nix/store/* from options,
        # or else the build will fail.
        prefixesToStrip = [ "${toString ./.}/" ];
        stripAnyPrefixes = lib.flip (lib.fold lib.removePrefix) prefixesToStrip;
        # Replace functions by the string <function>
        substFunction = x:
          if builtins.isAttrs x then lib.mapAttrs (name: substFunction) x
          else if builtins.isList x then map substFunction x
          else if lib.isFunction x then "<function>"
          else x;
      in unsafeDiscardStringContext (builtins.toJSON (optionsList));
    };

    # Some debuggging outputs
    debug = {
      inherit localNvimFiles drvRegistry requiredPlugins sortedPlugins registryByPath rawPluginBuckets mergedBuckets;
    };
  };
}
