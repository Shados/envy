# TODO add an assertion that all enabled source plugins have source pins, to
# make debugging that easier?
# TODO Things that could be improved/added in upstream nixpkgs vim plugins
# generally:
# - Track soft dependencies (before/after) on vim plugins
# - Settle on a plugin name schema; probably sanest to use simply "reponame"
#   for git-sourced plugins, and whatever vim-pi pulls for vim.org ones. Yes,
#   "reponame" likely will violate nixpkgs naming conventions regularly (e.g.
#   using '.' in attribute names), but the existing vimPlugins attribute set
#   doesn't match the camelCase naming convention to begin with.

# General TODO list:
# - Option to wrap per-plugin sections in individually named folds?

# We want to work as both a stand-alone module and a submodule, but submodules
# only get {config, lib, options} as arguments, so we have to wrap in another
# function to get pkgs
pkgs:
{ config, lib, options, ... }:
with lib;
let
  nvimLib = import ./lib.nix { nixpkgs = pkgs; };
  pluginHostConfig = ''
    " We set 'loaded_' variables for plugin hosts not provided by the module in
    " order to avoid expensive (and impure) dynamic searching for them
    ${if config.withPython2 then "let g:python_host_prog='${config.python2Env}/bin/python'" else "let g:loaded_python_provider=1"}
    ${if config.withPython3 then "let g:python3_host_prog='${config.python3Env}/bin/python'" else "let g:loaded_python3_provider=1"}
    let g:loaded_pythonx_provider=1
    let g:loaded_node_provider=1
    let g:loaded_ruby_provider=1
  '';

  initVimConfig = ''
    scriptencoding 'utf-8'
    ${config.earlyConfig}
    ${perPlugin.earlyConfig}
    ${pluginHostConfig}

    ${config.prePluginConfig}
    ${perPlugin.prePluginConfig}
  '' + optionalString (config.files != {}) ''
    " Direct modifications to rtp should be done prior to the plug#begin() call
    set runtimepath+=${localNvimFiles}
  '' + ''
    ${perPlugin.pluginLoaderConfig}
    ${perPlugin.postPluginConfig}
    ${config.postPluginConfig}

    filetype indent plugin on | syn on

    ${config.extraConfig}
  '';

  # This is used for declaratively generating the remote plugins manifest, so
  # it only really needs to ensure that remote plugins are loaded
  pluginOnlyConfig = ''
    scriptencoding 'utf-8'
    ${pluginHostConfig}
    ${perPlugin.barePluginLoaderConfig}

    filetype indent plugin on | syn on
  '';

  # localNvimFiles: A symlink tree of the configured extra nvim runtime files {{{
  localNvimFiles = pkgs.runCommand "config-nvim" {} (let
    filesJson = let
      fileList = mapAttrsToList (addPath) (filterAttrs (n: v: v.enable) config.files);
      # addPath :: String -> NvimFile -> { source :: String, target :: String }
      addPath = name: file: {
        inherit (file) source target;
      };
    in pkgs.writeText "local-nvim-files.json" (builtins.toJSON fileList);

    # We already need Lua due to nvim, and the other deps are pretty minimal --
    # doing this in bash would be less nice, jq isn't that great for working
    # with collections.
    luaDeps = ps: with ps; [ inspect luafilesystem rapidjson ];
    luaPkg = pkgs.luajit.withPackages luaDeps;
    luaBuilder = ./config-nvim-builder.lua;
  in ''
    ${luaPkg}/bin/lua ${luaBuilder} ${filesJson} $out
  '');
  # }}}

  # mergedBuckets: List of buckets with merged plugin directories (where possible) {{{
  mergedBuckets = let
    # mergeBucket :: [Plugin] -> [Either PluginDrv MergedPluginDrv]
    mergeBucket = bucket: let
      soloPlugins = filter (p: !isMergeablePlugin p) bucket;
      # isMergeablePlugin :: PluginDrv -> Bool
      isMergeablePlugin = plugin: !(
        # Any of these should prevent a plugin from being merged
           !plugin.mergeable
        || strListSet plugin.on
        || strListSet plugin.for
        || plugin.nvimrc.condition != null
        || plugin.pluginType == "local"
      );
      # strListSet :: Either String [String] -> Bool
      strListSet = strList: if isList strList then length strList > 0 else true;
      mergeablePlugins = filter (isMergeablePlugin) bucket;
      # Theoretically, could merge plugins in the same bucket with the same
      # "for", but probably not worthwhile
      mergedPlugin = let
        drv = pkgs.symlinkJoin {
          name = "merged-vim-plugins";
          paths = map (p: p.rtp) mergeablePlugins;
          postBuild = ''
            # Rebuild help tag index
            if [ -d "$out/doc" ]; then
              if [ -e "$out/doc/tags" ]; then
                echo "Removing linked help tags"
                rm -f "$out/doc/tags"
              fi
              echo "Building help tags for merged plugins"
              if ! ${config.neovimPackage}/bin/nvim -N -u NONE -i NONE -n -E -s -V1 -c "helptags $out/doc" +quit!; then
                echo "Failed to build help tags!"
                exit 1
              fi
            else
              echo "No docs available"
            fi
          '';
        };
      in drv // {
        rtp = "${drv}/";
        pluginType = "source";
        nvimrc.condition = null;
        # Needed for rplugin generation
        remote = {
          python2 = any (p: p.remote.python2) mergeablePlugins;
          python3 = any (p: p.remote.python3) mergeablePlugins;
        };
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
  rawPluginBuckets = let
    # addToBuckets :: [String] -> [[PluginDrv]] -> [String] -> [[PluginDrv]]
    addToBuckets = done: buckets: rem: let
      buckets' = buckets ++ [ currentBucket ];
      # List of plugins whose dependencies (soft and hard) are satisfied by the
      # plugins already done
      currentBucket = filter (p: isSatisfied p) rem;
      # isSatisfied :: PluginDrv -> Bool
      isSatisfied = plug: let
        # Set of plugins that this plugin must be ordered after, and that are
        # part of the plugin dependency closure of this neovim config
        after = filter (n: hasAttr n requiredPlugins) depIndex.${plug.depName}.after;
      in all (dep: elem dep done) after;

      rem' = filter (plug: ! isSatisfied plug) rem;
      done' = done ++ (map (plug: plug.depName) currentBucket);
    in if length rem' > 0
      then addToBuckets done' buckets' rem'
      else buckets';
  in addToBuckets [] [] (attrValues requiredPluginDrvs);
  # }}}

  # depIndex: Maps plugin names to the plugins that should be loaded before/after them {{{
  depIndex = let
    fullIndex = foldl' (addDepInfo) {} (mapAttrsToList (nameValuePair) config.fullPluginRegistry);
    # addDepInfo :: { Plugin } -> {name :: String, value :: Plugin } ->
    #   { Plugin }
    addDepInfo = index: {name, value}: let
      plugin = value;

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
        map (plugName: nameValuePair plugName { before = [ name ]; }) (depStrings ++ plugin.after or [])
        ++ singleton (nameValuePair name { before = plugin.before or []; });
      depStrings = map (plugDepAsString) (plugin.dependencies or []);

      afterUpdates =
        (map (plugName: nameValuePair plugName { after = [ name ]; }) (plugin.before or []))
        ++ singleton (nameValuePair name { after = plugin.after or [] ++ depStrings;});
    in updatedIndex;
  in fullIndex;
  # }}}

  # perPlugin: Various lists of per-plugin init.vim lines {{{
  perPlugin = let
    pluginLoaderSection = plugLines: ''
      source ${config.baseVimPlugins.vim-plug.rtp}/plug.vim
      call plug#begin('/dev/null')
      ${concatMapStringsSep "\n" (plugLine: "  ${plugLine}") plugLines}
      call plug#end()
    '';
    fullPlugCmd = plugin: options: "${basePlugCmd plugin}, ${formattedPlugOptions options}";
    basePlugCmd = plugin: "Plug '${if isLocal plugin then plugin.dir else plugin.rtp}'";
    formattedPlugOptions = options: "{${concatStringsSep ", " (mapAttrsToList (n: v: "'${n}': ${formatPlugOption n v}") options)}}";

    formatPlugOption = n: v:
           if n == "frozen" then toString v
      else if n == "for"    then vimStringList v
      else if n == "on"     then vimStringList v
      else assert false; null;
    vimStringList = plugOpt:
           if builtins.typeOf plugOpt == "string"  then vimString plugOpt
      else if builtins.typeOf plugOpt == "list"    then "[${concatMapStringsSep ", " (vimString) plugOpt}]"
      else assert false; null;
    vimString = s: assert builtins.typeOf s == "string"; "'${s}'";
    # Filter out non-vim-plug options, and defaulted values (null and empty-list)
    filterPlugOpts = n: v: elem n vimPlugAttrs && v != null && (builtins.typeOf v != "list" || length v > 0);
    plugOptions = plugin: optionalAttrs (!isLocal plugin) { frozen = 1; } // (filterAttrs (filterPlugOpts) plugin);
    isLocal = plugin: plugin.pluginType == "local";

    perPluginConfigFor = section: plugins: let
      matchingPlugins = filter (plugin: plugin.nvimrc.${section} != null) plugins;
    in concatMapStringsSep "\n\n" (plugin: plugin.nvimrc.${section}) matchingPlugins;

    plugList = if config.mergePlugins then flatten mergedBuckets else sortedPlugins;
  in {
    # Neovim config for loading the plugins
    # TODO source to user .vim file at configurable path for run-time vim-plug
    # plugin loading? can't have multiple plug#begin/end blocks -- see
    # https://github.com/junegunn/vim-plug/issues/615
    pluginLoaderConfig = let
      plugLineForPlugin = plugin:
        if plugin.nvimrc.condition != null
        then ''
          if ${plugin.nvimrc.condition}
            ${fullPlugCmd plugin (plugOptions plugin)}
          endif
        ''
        else fullPlugCmd plugin (plugOptions plugin);
    in pluginLoaderSection (map (plugLineForPlugin) plugList);
    barePluginLoaderConfig = let
      remotePlugins = filter (plug: any (v: v == true) (attrValues plug.remote)) plugList;
      barePlugLineForPlugin = plugin: let
        barePlugOptions = filterAttrs (n: v: !(elem n [ "on" "for" ])) (plugOptions plugin);
      in fullPlugCmd plugin barePlugOptions;
    in pluginLoaderSection (map (barePlugLineForPlugin) remotePlugins);

    # Neovim config fragments for pre- and post-plugin-loading
    # NOTE: We use sortedPlugins instead of plugList here so we don't have to
    # merge these configs in merged plugins
    prePluginConfig = perPluginConfigFor "prePlugin" sortedPlugins;
    postPluginConfig = perPluginConfigFor "postPlugin" sortedPlugins;
    earlyConfig = perPluginConfigFor "early" sortedPlugins;
  };
  # }}}

  # sortedPlugins: List of required plugin drvs sorted into valid loading order
  sortedPlugins = flatten rawPluginBuckets;

  # pluginSourceMap: Plugin:source mappings, for prefetching plugin sources {{{
  pluginSourceMap = let
    # Construct a list of (name,{...}@srcSpec) pairs
    pluginSources = mapAttrs (sourcesForPlugin) sourcePlugins;

    # sourcesForPlugin :: String -> TaggedPlugin ->
    #   { source :: String, branch :: String, tag :: String, commit :: String }
    sourcesForPlugin = name: spec:
      (filterAttrs (n: v: elem n sourceAttrs && v != null) spec) // {
        # Default source url to name, assuming the name is a vim-plug
        # compatible shortname
        source = if spec.source != null then spec.source else name;
      };
  in pluginSources;
  # }}}

  sourcePlugins = filterAttrs (n: v: v ? pluginType && v.pluginType == "source") taggedPluginRegistry;

  # requiredPluginDrvs: Dependency closure of plugin derivations that need to be installed
  requiredPluginDrvs = mapAttrs (name: _: composedRegistry.${name}) requiredPlugins;

  # requiredPlugins: Dependency closure of raw plugins that need to be installed
  requiredPlugins = filterAttrs (n: v: v.enable) config.fullPluginRegistry;

  # composedRegistry: pluginRegistry composed with source pins to make drvs {{{
  # Takes the plugin registry and composes it with the source pins to ensure
  # that all members are actual plugin derivations. Additionally, associates
  # the registry name for the plugin with the derivation (via `passthru`) to
  # make dependency tracking simple.
  composedRegistry = let
    # composePlugin :: String -> TaggedPlugin -> PluginDrv
    composePlugin = pluginName: plugin:
      # Source plugin
      if plugin.pluginType == "source" then buildPluginFromSourcePin pluginName plugin
      # Store-path src plugin
      else if plugin.pluginType == "path" then buildPluginFromPath pluginName plugin
      # Upstream/nixpkgs/derivation plugin
      else if plugin.pluginType == "upstream" then overrideUpstreamPlugin pluginName plugin
      # "Local", unmanaged plugin
      else plugin // { depName = pluginName; };

    # overrideUpstreamPlugin :: String -> Derivation -> PluginDrv
    overrideUpstreamPlugin = pluginName: wrappedDrv: overridePassthru
      wrappedDrv.source
      ({ depName = pluginName; } // (filterPluginSpec wrappedDrv));
    # overridePassthru :: Derivation -> AttrSet -> Derivation
    overridePassthru = drv: passthru: drv.overrideAttrs(oldAttrs: {
      passthru = (oldAttrs.passthru or {}) // passthru;
    });
  in mapAttrs (composePlugin) taggedPluginRegistry;
  # }}}

  # taggedPluginRegistry: pluginRegistry with source-type tagging {{{
  taggedPluginRegistry = let
    # amendPluginRegistration :: String -> Plugin -> TaggedPlugin
    amendPluginRegistration = name: plugin:
      if plugin.dir != null
        then  plugin // { pluginType = "local"; }

      else if plugin ? source && isDerivation plugin.source && hasPrefix "vimplugin-" plugin.source.name
        then  plugin // { pluginType = "upstream"; }

      else if plugin ? source && ((builtins.typeOf plugin.source) == "path" || isDerivation plugin.source)
        then  plugin // { pluginType = "path"; }

      else    plugin // { pluginType = "source"; };
  in mapAttrs (amendPluginRegistration) config.fullPluginRegistry;
  # }}}

  # registryWithDeps :: { Plugin } -> { Plugin }
  # Add any missing dependency plugins referenced in the registry to the registry. {{{
  # Takes a plugin registry, and generates default entries for missing
  # dependencies, as well as ensures all dependencies of enabled plugins are
  # enabled (recursively).
  registryWithDeps = baseRegistry: let
    # Ensure dependencies of enabled plugins are enabled, recursively
    withEnabledDeps = foldl' (enableDep) withDeps depsToEnable;
    depsToEnable = let
      deps = concatLists (mapAttrsToList (n: _: getDeps n) enabledPlugins);
      enabledPlugins = filterAttrs (n: v: v.enable) withDeps;
      # getDeps :: String -> [String]
      getDeps = plugName: let
        plugDeps = map (plugDepAsString) (withDeps.${plugName}.dependencies or []);
      in plugDeps ++ concatMap (getDeps) plugDeps;
    in deps;
    # enableDep :: { Plugin } -> String -> { Plugin }
    enableDep = registry: name: registry // {
      ${name} = registry.${name} // { enable = true; };
    };

    # Add missing dependencies
    withDeps = foldl'
      (registry: dep: registry // { ${dep.name} = dep.value; })
      baseRegistry
      pluginDeps;
    pluginDeps = flatten (mapAttrsToList (unresolvedPluginDeps) baseRegistry);
    # unresolvedPluginDeps :: String -> Plugin -> [Plugin]
    unresolvedPluginDeps = pluginName: spec:
      map (unresolvedPluginSpec) (filter (isUnresolvedPlugin) spec.dependencies);
    # isUnresolvedPlugin :: Either String Plugin -> Bool
    isUnresolvedPlugin = dep: let
      depName = if builtins.typeOf dep == "string" then dep
                else dep.pname;
    in !(hasAttr depName baseRegistry);
    # unresolvedPluginSpec :: Either String Plugin -> Plugin
    unresolvedPluginSpec = dep: let
      spec = (if builtins.typeOf dep == "string"
        then {}
        else wrapUpstreamPluginDrv dep.pname dep
      ) // { enable = true; };
      name = if builtins.typeOf dep == "string"
        then dep
        else dep.pname;
    in nameValuePair name spec;
  in withEnabledDeps;
  # }}}

  # defaultPluginRegistry: plugin registry built by wrapping vimPlugins {{{
  # Takes base vimPlugins set and wraps each derivation in a pluginConfigType
  # attribute set.
  defaultPluginRegistry = let
    baseRegistry = mapAttrs (wrapUpstreamPluginDrv) (filterVimPlugins config.baseVimPlugins);
    # filterVimPlugins :: AttrSet -> { Derivation }
    # Filter out functions resulting from overlay application, and other
    # irrelvant attributes
    filterVimPlugins = attrs: filterAttrs (n: v: isDerivation v) attrs;
  in baseRegistry;
  # }}}

  # Helpers {{{
  sourceAttrs = [ "source" "branch" "tag" "commit" ];
  # dir and rtp not included because we effectively apply them earlier
  vimPlugAttrs = [ "on" "for" ];
  # pluginConfigType attributes that should be retained in the composed plugin
  # derivations
  pluginDrvAttrs = filter (n: !elem n sourceAttrs) (attrNames pluginConfigType.options)
    ++ singleton "pluginType";

  # TODO: Is there anything else we can automatically infer?
  # wrapUpstreamPluginDrv :: String -> Derivation -> Plugin
  wrapUpstreamPluginDrv = name: pluginDrv: {
    source = pluginDrv;
    remote = {}
      # NOTE python2/python3 are behind optionalAttrs as we don't want the user
      # to have to mkForce in order to fix a false-negative
      // optionalAttrs (pluginDrv ? pythonDependencies) {
        python2 = true;
        python2Deps = pluginDrv.pythonDependencies;
      }
      // optionalAttrs (pluginDrv ? python3Dependencies) {
        python3 = true;
        python3Deps = pluginDrv.python3Dependencies;
      };
    dependencies = pluginDrv.dependencies or [];
    binDeps = pluginDrv.propagatedBuildInputs or [];
  };

  # buildPluginFromSourcePin :: String -> Plugin -> PluginDrv
  buildPluginFromSourcePin = pluginName: spec: let
    pin = config.sourcePins.${pluginName};
    pname = last (splitString "/" pluginName);
    inherit (pin) version;
    src = sourceFromPin pin;
  in buildPlugin pluginName pname spec version src;

  # buildPluginFromPath :: String -> Plugin -> PluginDrv
  buildPluginFromPath = pluginName: spec: let
    pname = pluginName;
    version = "frompath";
    src = spec.source;
  in buildPlugin pluginName pname spec version src;

  buildPlugin = depName: pname: spec: version: src: pkgs.vimUtils.buildVimPluginFrom2Nix (rec {
    inherit pname version src;
    name = "${pname}-${version}";
    passthru = {
      inherit depName;
      # Add the rest of the plugin config so we can directly build the vim
      # config from the composed plugins
    } // (filterPluginSpec spec);
  } // optionalAttrs (spec.rtp != null) { rtpPath = rtp; });

  # filterPluginSpec :: Plugin -> AttrSet
  filterPluginSpec = spec: filterAttrs (n: v: elem n pluginDrvAttrs) spec;

  # sourceFromPin :: {SourcePin} -> StorePath
  sourceFromPin = pin: pkgs.fetchgit { inherit (pin) url rev sha256; };

  # getRemoteDeps :: String -> Any (Bool ExtraPython2Package ExtraPython3Package)
  getRemoteDeps = attrname: map (plugin: plugin.remote.${attrname});
  # plugDepAsString :: Either String Derivation -> String
  plugDepAsString = dep: if isString dep then dep else dep.pname;
  # buildPythonEnv :: String -> { Derivation } ->
  #   Either ExtraPython2Package ExtraPython3Package -> Derivation
  buildPythonEnv = vimDepName: pyPackages: extraPackages: let
    pluginPythonPackages = getRemoteDeps vimDepName (sortedPlugins);
  in pyPackages.python.withPackages (ps:
      [ ps.pynvim ]
      ++ (extraPackages ps)
      ++ (concatMap (f: f ps) pluginPythonPackages)
    );

  # requiresRemoteHost :: String -> Bool
  requiresRemoteHost = remoteHost: any (plugin: let
    in plugin.remote.${remoteHost} == true) sortedPlugins;

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
    example = literalExample "(packageSet: with packageSet: [ ${examplePackages} ])";
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
  extraPython2PackageType = mkLangPackagesType
    "python2"
    (val: isList (val pkgs.python2Packages));
  extraLuaPackageType = mkLangPackagesType
    "lua"
    (val: true);
  # langPackagesMergeFunc :: Any -> [({Derivation} -> [Derivation])] ->
  #   ({Derivation} -> [Derivation])
  langPackagesMergeFunc = loc: defs:
    packageSet: foldr (a: b: a ++ b) [] (map (f: f packageSet) (getValues defs));

  sourcePin.options = {
    url = mkOption {
      type = with types; str;
      description = ''
        `pkgs.fetchgit-compatible` git url string.
      '';
    };
    rev = mkOption {
      type = with types; str;
      description = ''
        `pkgs.fetchgit-compatible` git revision string.
      '';
    };
    sha256 = mkOption {
      type = with types; str;
      description = ''
        `pkgs.fetchgit-compatible` sha256 string.
      '';
    };
    version = mkOption {
      type = with types; str;
      description = ''
        Version string appropriate for a nixpkgs derivation.
      '';
    };
    # TODO This isn't really used right now, but is intended to allow for
    # supporting multiple types of fetch instead of just git.
    fetchType = mkOption {
      type = with types; enum [ "git" "github" ];
      description = ''
        Type of the fetcher to use.
      '';
    };
  };

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
        let name' = "config-nvim-${replaceChars [ " " ] [ "_" ] (baseNameOf name)}";
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

        Items can be either strings representings vim-plug-compatible git
        repository urls, base `vimPlugins` attribute names, or existing vim
        plugin derivations.
      '';
      type = with types; listOf (either str package);
      default = [];
    };
    before = mkOption {
      description = ''
        List of other vim plugins that this plugin should be loaded *before*.

        This can be seen as a "soft" form of making this plugin a dependency of
        each of the listed plugins.

        Items must be strings representings either vim-plug-compatible git
        repository urls, or base `vimPlugins` attribute names.
      '';
      type = with types; listOf str;
      default = [];
    };
    after = mkOption {
      description = ''
        List of other vim plugins that this plugin should be loaded *after*.

        This can be seen as a "soft" form of making each of the listed plugins
        dependencies of this plugin.

        Items must be strings representings either vim-plug-compatible git
        repository urls, or base `vimPlugins` attribute names.
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
      python2 = mkRemoteHostOption "Python 2";
      python2Deps = mkLangPackagesOption "Python 2" extraPython2PackageType "pandas jedi";
      python3 = mkRemoteHostOption "Python 3";
      python3Deps = mkLangPackagesOption "Python 3" extraPython3PackageType "python-language-server";
    };
    nvimrc = {
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
      early = mkOption {
        description = ''
          Extra lines of `init.vim` configuration associated with this plugin,
          that need to be as early as possible in the file.

          Leave null if no such extra configuration is required.
        '';
        type = with types; nullOr lines;
        default = null;
      };
      prePlugin = mkOption {
        description = ''
          Extra lines of `init.vim` configuration associated with this plugin,
          that need to be executed before the plugin loading.

          Leave null if no such extra configuration is required.
        '';
        type = with types; nullOr lines;
        default = null;
      };
      postPlugin = mkOption {
        description = ''
          Extra lines of `init.vim` configuration associated with this plugin,
          that need to be executed after the plugin loading.

          Leave null if no such extra configuration is required.
        '';
        type = with types; nullOr lines;
        default = null;
      };
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

        Leave as `null` to let the module infer the source as a vim-plug
        shortname from the name of this `pluginConfig` attribute.

        Otherwise, set to a string representing a vim-plug-compatible git
        repository url, an existing vim plugin derivation, or to a Nix store
        path to build a vim plugin derivation from.

        If left null or set to a string, a pin for the source must be present
        in `sourcePins` in order to build the neovim configuration.
      '';
      default = null;
      type = with types; nullOr (either package (either str path));
    };
    branch = mkOption {
      description = ''
        Branch of the git source to fetch and use. The `tag` and `commit`
        options effectively override this.

        Leave as `null` to simply use the branch of `HEAD` (typically, `master`).
      '';
      type = with types; nullOr str;
      default = null;
    };
    tag = mkOption {
      description = ''
        Tag of the git source to fetch and use. The `commit` option effectively
        overrides this.

        Leave as `null` to simply use the `HEAD`.
      '';
      type = with types; nullOr str;
      default = null;
    };
    commit = mkOption {
      description = ''
        Commit of the git source to fetch and use.

        Leave as `null` to simply use the `HEAD`.
      '';
      type = with types; nullOr str;
      default = null;
    };
    # TODO replace this by just handling strings in source, maybe?
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
    on = mkOption {
      description = ''
        One or more command or &lt;Plug&gt;-mappings that should trigger on-demand
        loading of this plugin.

        Can be specified with either a single string or list of strings.
      '';
      type = with types; either str (listOf str);
      default = [];
    };
    for = mkOption {
      description = ''
        One or more filetypes that should trigger on-demand loading of this
        plugin.

        Can be specified with either a single string or list of strings.
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
      # Effectively defaulted to defaultPluginRegistry later
      default = {};
      example = literalExample ''
        {
          # A "source" plugin, where the source is inferred from the attribute
          # name, treated as a vim-plug-compatible shortname
          "bagrat/vim-buffet" = {
            enable = true;
            dependencies = [
              "lightline-vim"
            ];
            # The specific commit to use for the source checkout
            commit = "044f2954a5e49aea8625973de68dda8750f1c42d";
            nvimrc = {
              prePlugin = '''
                " Customize vim-workspace colours based on gruvbox colours
                function g:WorkspaceSetCustomColors()
                  highlight WorkspaceBufferCurrentDefault guibg=#a89984 guifg=#282828
                  highlight WorkspaceBufferActiveDefault guibg=#504945 guifg=#a89984
                  highlight WorkspaceBufferHiddenDefault guibg=#3c3836 guifg=#a89984
                  highlight WorkspaceBufferTruncDefault guibg=#3c3836 guifg=#b16286
                  highlight WorkspaceTabCurrentDefault guibg=#689d6a guifg=#282828
                  highlight WorkspaceTabHiddenDefault guibg=#458588 guifg=#282828
                  highlight WorkspaceFillDefault guibg=#3c3836 guifg=#3c3836
                  highlight WorkspaceIconDefault guibg=#3c3836 guifg=#3c3836
                endfunction
              ''';
              postPlugin = '''
                " vim-workspace
                " Disable lightline's tabline functionality, as it conflicts with this
                let g:lightline.enable = { 'tabline': 0 }
                " Prettify
                let g:workspace_powerline_separators = 1
                let g:workspace_tab_icon = "\uf00a"
                let g:workspace_left_trunc_icon = "\uf0a8"
                let g:workspace_right_trunc_icon = "\uf0a9"
              ''';
            };
          };

          "Shados/nvim-moonmaker" = {
            enable = false;
            # Decide whether or not to load at run-time based on the result of
            # a VimL expression
            nvimrc.condition = "executable('moonc')";
          };

          vim-auto-save = {
            enable = true;
            # Lazily load on opening a tex file
            for = "tex";
          };

          nerdtree = {
            enable = true;
            # Lazily load on command usage
            on = "NERDTreeToggle";
            nvimrc.postPlugin = '''
              " Prettify NERDTree
              let NERDTreeMinimalUI = 1
              let NERDTreeDirArrows = 1
            ''';
          };

          # Use upstream LanguageClient-neovim derivation
          LanguageClient-neovim.enable = true;

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
            # vim-devicons needs to be loaded after these plugins, if they
            # are being used, as per its installation guide
            after = [
              "nerdtree" "vim-airline" "ctrlp-vim" "powerline/powerline"
              "denite-nvim" "unite-vim" "lightline-vim" "vim-startify"
              "vimfiler" "vim-flagship"
            ];
          };
        }
      '';
    };
    baseVimPlugins = mkOption {
      # Can't make this e.g. `attrsOf package` because there *may* be non-package
      # members, and there *definitely* are in nixpkgs.vimPlugins
      type = with types; attrs;
      default = let
        plugins = pkgs.callPackage "${pkgs.path}/pkgs/misc/vim-plugins/generated.nix" {
          inherit (pkgs.vimUtils) buildVimPluginFrom2Nix;
          inherit overrides;
        };
        overrides = pkgs.callPackage "${pkgs.path}/pkgs/misc/vim-plugins/overrides.nix" { 
          inherit (pkgs.darwin.apple_sdk.frameworks) Cocoa CoreFoundation CoreServices;
          inherit (pkgs.vimUtils) buildVimPluginFrom2Nix;
          inherit (pkgs) llvmPackages;
        };
      in plugins;
      defaultText = "base vimPlugins without aliases";
      description = ''
        Base set of vim plugin derivations to resolve string/name-based plugin
        dependencies against.
      '';
    };
    sourcePins = mkOption {
      type = with types; attrsOf (submodule sourcePin);
      description = ''
        Attribute set of source pins for vim plugins. Attribute names should
        map directly to `pluginRegistry` attribute names.
      '';
      default = {};
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


    # For managing non-plugin-related init.vim configuration fragments
    extraConfig = mkOption {
      type = with types; lines;
      default = "";
      description = ''
        Extra lines of `init.vim` configuration to append to the generated
        ones.
      '';
    };
    prePluginConfig = mkOption {
      type = with types; lines;
      default = "";
      description = ''
        Extra lines of `init.vim` configuration that need to be executed before
        the plugin loading.
      '';
    };
    earlyConfig = mkOption {
      type = with types; lines;
      default = "";
      description = ''
        Extra lines of `init.vim` configuration that need to be as early as
        possible in the file.
      '';
    };
    postPluginConfig = mkOption {
      type = with types; lines;
      default = "";
      description = ''
        Extra lines of `init.vim` configuration that need to be executed after
        the plugin loading.
      '';
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
        Nix these would typically be locally-managed files in the
        `~/.config/nvim` folder.
      '';
      example = literalExample ''
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
      example = literalExample "(ps: with ps; [ python-language-server ])";
      description = ''
        A function in `python.withPackages` format, which returns a list of
        Python 3 packages required for your plugins to work.

        Using the per-plugin `python3Deps` is strongly preferred; this should
        only be necessary if you need some Python 3 packages made available to
        neovim for a plugin that is *not* being managed by this module.
      '';
    };

    withPython2 = mkOption {
      type = types.bool;
      default = requiresRemoteHost "python2";
      description = ''
        Enable Python 2 provider. Set to `true` to use Python 2 plugins.
      '';
    };
    extraPython2Packages = mkOption {
      type = extraPython2PackageType;
      default = (_: []);
      defaultText = "ps: []";
      example = literalExample "(ps: with ps; [ pandas jedi ])";
      description = ''
        A function in `python.withPackages` format, which returns a list of
        Python 2 packages required for your plugins to work.

        Using the per-plugin `python2Deps` is strongly preferred; this should
        only be necessary if you need some Python 2 packages made available to
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
    fullPluginRegistry = mkOption {
      type = with types; attrsOf (submodule pluginConfigType);
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Base `pluginRegistry`, with any dependency plugins not already in the
        registry added to it.
      '';
    };
    pluginSourcesJson = mkOption {
      type = with types; path;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Path to JSON file mapping plugin names to source objects, used to
        prefetch sources for plugins. Generated automatically by this module.
      '';
    };
    requiredPluginsJson = mkOption {
      type = with types; path;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Path to JSON file listing required plugins, used to prefetch sources
        for plugins. Generated automatically by this module.
      '';
    };
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
    python2Env = mkOption {
      type = with types; nullOr package;
      readOnly = true;
      internal = true;
      visible = false;
      description = ''
        Generated Python 2 environment containing the plugin host package, the
        required per-plugin Python 2 depenedencies, and the specified
        `extraPython2Packages`.
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
        `extraPython2Packages`.
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
      readOnly = true;
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
    # TODO this would be nice to have; but NixOS assertions are implemented as
    # an external module themselves, not an internal/bultin module as part of
    # evalModules... well, I could eval with it.
    # assertions = [
    #   (let
    #     requiredSourcePlugins = flip filterAttrs requiredPlugins (n: _: hasAttr n sourcePlugins);
    #     missingSources = filter (n: !hasAttr n config.sourcePins) (attrNames requiredSourcePlugins);
    #   in { assertion = all (n: hasAttr n config.sourcePins) (attrNames requiredSourcePlugins);
    #     message = "Some plugins are missing sources: #{concatStringsSep ', ' missingSources}";
    #   })
    # ];
    # Set here because it shouldn't be mkOptionDefault
    pluginRegistry = defaultPluginRegistry;

    # Setting read-only options
    neovimRC = pkgs.writeText "init.vim" initVimConfig;
    pluginOnlyRC = pkgs.writeText "plugin-only-init.vim" pluginOnlyConfig;
    pluginSourcesJson = pkgs.writeText "nvim-plugin-configs.json" (builtins.toJSON pluginSourceMap);
    requiredPluginsJson = pkgs.writeText "nvim-required-plugins.json" (builtins.toJSON (attrNames requiredPlugins));
    depIndexJson = pkgs.writeText "nvim-dependenxy-index.json" (builtins.toJSON (depIndex));
    python2Env = buildPythonEnv "python2Deps" pkgs.pythonPackages config.extraPython2Packages;
    python3Env = buildPythonEnv "python3Deps" pkgs.python3Packages config.extraPython3Packages;
    luaModules = concatMap (plugin: singleton plugin.luaDeps) sortedPlugins;
    binDeps = concatMap (plugin: plugin.binDeps) sortedPlugins;
    wrappedNeovim = let
      configureNeovim = pkgs.callPackage ./wrapper.nix { luaPkg = pkgs.luajit; };
    in configureNeovim config.neovimPackage config;
    generatePluginManifest = any (v: v) (map (requiresRemoteHost) [ "python2" "python3" ]);
    fullPluginRegistry = registryWithDeps (config.pluginRegistry);

    lib = {
      inherit (nvimLib) escapedName pinPathFor pinFromPath fillPinsFromDir;
      inherit buildPluginFromPath;

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
      in builtins.unsafeDiscardStringContext (builtins.toJSON (optionsList));
    };

    # Some debuggging outputs
    debug = {
      sortedPluginList = pkgs.writeText "vim-plugin-sorted-list.json" (builtins.toJSON sortedPlugins);
      pluginOnlyConfigFile = pkgs.writeText "plugin-only-config.json" pluginOnlyConfig;
      inherit localNvimFiles composedRegistry;
      pluginBuckets = pkgs.writeText "buckets.json" (builtins.toJSON rawPluginBuckets);
      mergedPluginBuckets = pkgs.writeText "merged-buckets.json" (builtins.toJSON mergedBuckets);
    };
  };
}
