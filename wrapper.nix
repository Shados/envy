{ stdenv, lib, makeWrapper
, writeText
, luajit
, neovimUtils
, neovim-unwrapped
}:
let
  inherit (lib) concatMap concatStringsSep escapeShellArg length makeBinPath optional optionals optionalString stringLength;
  wrapper = cfg:
  let

    bin = "${neovim-unwrapped}/bin/nvim";
    binPath = makeBinPath allBinDeps;
    allBinDeps = cfg.binDeps ++ cfg.extraBinPackages;

    luaPathPrefix = drv: "${drv}/share/lua/${luajit.luaversion}";
    luaCPathPrefix = drv: "${drv}/lib/lua/${luajit.luaversion}";
    makeLuaPath = drv: [ "${luaPathPrefix drv}/?/init.lua" "${luaPathPrefix drv}/?.lua" ];
    makeLuaCPath = drv: [ "${luaCPathPrefix drv}/?/init.so" "${luaCPathPrefix drv}/?.so" ];
    luaEnv = luajit.withPackages (ps:
      concatMap (f: f ps) cfg.luaModules
    );

    fullNvimWrapperArgs = baseNvimWrapperArgs ++ [
      ''--add-flags'' ''"--cmd \"luafile ${cfg.neovimRC}\""''
      "--argv0 nvim"
      "--set NVIM_SYSTEM_RPLUGIN_MANIFEST $out/rplugin.vim"
    ];

    baseNvimWrapperArgs = [
      bin
      "$out/bin/nvim"
      ''--add-flags'' ''"--cmd \"lua ${providerLuaRc}\""''
    ]
    ++ optional (allBinDeps != []) (makeSuffixArg "PATH" ":" binPath)
    ++ optionals (cfg.luaModules != []) [
      (makeSuffixListArg "LUA_PATH" ";" (makeLuaPath luaEnv))
      (makeSuffixListArg "LUA_CPATH" ";" (makeLuaCPath luaEnv))
    ]
    ;
    makeSuffixArg = var: sep: val: "--suffix ${escapeShellArg var} ${escapeShellArg sep} ${escapeShellArg val}";
    makeSuffixListArg = var: sep: list: makeSuffixArg var sep "${concatStringsSep sep list}";

    makeNvimWrapper = wrapperArgs: ''
      makeWrapper \
        ${concatStringsSep " \\\n  " wrapperArgs}
    '';

    providerLuaRc = neovimUtils.generateProviderRc {
      inherit (cfg) withPython3;
      withNodeJs = false;
      withPerl = false;
      withRuby = false;
    };

  in stdenv.mkDerivation rec {
    name = "neovim-configured-${lib.getVersion neovim-unwrapped}";
    buildCommand = ''
      if [ ! -x "${bin}" ]
      then
          echo "cannot find executable file \`${bin}'"
          exit 1
      fi

      ${makeNvimWrapper baseNvimWrapperArgs}
    ''
    + optionalString (stdenv.isLinux) ''
        mkdir -p $out/share/applications/
        substitute ${neovim-unwrapped}/share/applications/nvim.desktop $out/share/applications/nvim.desktop \
          --replace 'Name=Neovim' 'Name=Neovim wrapper'
    ''
    + lib.optionalString cfg.withPython3 ''
        makeWrapper ${cfg.python3Env.interpreter} $out/bin/nvim-python3 --unset PYTHONPATH --unset PYTHONSAFEPATH
    ''
    + optionalString (cfg.generatePluginManifest) ''
      echo "Generating remote plugin manifest"
      export NVIM_RPLUGIN_MANIFEST=$out/rplugin.vim
      export HOME="$PWD"
      # Launch neovim with a vimrc file containing only the generated plugin
      # code. Pass various flags to disable temp file generation
      # (swap/viminfo) and redirect errors to stderr.
      # Only display the log on error since it will contain a few normally
      # irrelevant messages.
      if ! $out/bin/nvim \
        --cmd "luafile ${cfg.pluginOnlyRC}" \
        -i NONE -n \
        -E -V1rplugins.log -s \
        +UpdateRemotePlugins +quit! > outfile 2>&1; then
          cat outfile
          echo -e "\nGenerating rplugin.vim failed!"
          exit 1
      fi
      unset NVIM_RPLUGIN_MANIFEST
    '' + ''
      rm $out/bin/nvim
      touch $out/rplugin.vim
      ${makeNvimWrapper fullNvimWrapperArgs}
    '';

    preferLocalBuild = true;

    nativeBuildInputs = [ makeWrapper ];
    passthru = { unwrapped = neovim-unwrapped; };

    meta = neovim-unwrapped.meta // {
      description = neovim-unwrapped.meta.description;
      hydraPlatforms = [ ];
      # prefer wrapper over the package
      priority = (neovim-unwrapped.meta.priority or 0) - 1;
    };
  };
in lib.makeOverridable wrapper
