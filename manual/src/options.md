# A. Configuration Options

<div class="option">

### `_module.args`

<div class="option_description">

Additional arguments passed to each module in addition to ones like `lib`,
`config`, and `pkgs`, `modulesPath`.

This option is also available to all submodules. Submodules do not inherit args
from their parent module, nor do they provide args to their parent module or
sibling submodules. The sole exception to this is the argument `name` which is
provided by parent modules to a submodule and contains the attribute name the
submodule is bound to, or a unique generated name if it is not bound to an
attribute.

Some arguments are already passed by default, of which the following *cannot* be
changed with this option:

  - {var}`lib`: The nixpkgs library.

  - {var}`config`: The results of all options after merging the values from all
    modules together.

  - {var}`options`: The options declared in all modules.

  - {var}`specialArgs`: The `specialArgs` argument passed to `evalModules`.

  - All attributes of {var}`specialArgs`
    
    Whereas option values can generally depend on other option values thanks to
    laziness, this does not apply to `imports`, which must be computed
    statically before anything else.
    
    For this reason, callers of the module system can provide `specialArgs`
    which are available during import resolution.
    
    For NixOS, `specialArgs` includes {var}`modulesPath`, which allows you to
    import extra modules from the nixpkgs package tree without having to somehow
    make the module aware of the location of the `nixpkgs` or NixOS directories.
    
    ``` 
    { modulesPath, ... }: {
      imports = [
        (modulesPath + "/profiles/minimal.nix")
      ];
    }
    ```

For NixOS, the default value for this option includes at least this argument:

  - {var}`pkgs`: The nixpkgs package set according to the {option}`nixpkgs.pkgs`
    option.

</div>

<div class="option_properties">

  - *Type:* lazy attribute set of raw value

</div>

</div>

<div class="option">

### `configLanguage`

<div class="option_description">

The language you wish to use for user-supplied configuration line options
(`extraConfig`, `prePluginConfig`, and
`pluginRegistry.<pluginName>.extraConfig`).

</div>

<div class="option_properties">

  - *Type:* one of "vimscript", "lua", "moonscript"

  - *Default:* `"vimscript"`

</div>

</div>

<div class="option">

### `extraBinPackages`

<div class="option_description">

A list of derivations containing executables that need to be available in the
`$PATH` of the neovim process for this plugin to use.

Using the per-plugin `binDeps` is generally preferred; this should only be
necessary if you need to make executables available for either:

  - A plugin that is *not* being managed by this module.
  - A binding or function in your `init.vim`, or other direct use from within
    neovim.

</div>

<div class="option_properties">

  - *Type:* list of package

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `extraConfig`

<div class="option_description">

Extra lines of `init.vim` configuration to append to the generated ones,
immediately following any `pluginRegistry.<pluginName>.extraConfig` config
lines.

</div>

<div class="option_properties">

  - *Type:* strings concatenated with "\\n"

  - *Default:* `""`

</div>

</div>

<div class="option">

### `extraPython3Packages`

<div class="option_description">

A function in `python.withPackages` format, which returns a list of Python 3
packages required for your plugins to work.

Using the per-plugin `python3Deps` is strongly preferred; this should only be
necessary if you need some Python 3 packages made available to neovim for a
plugin that is *not* being managed by this module.

</div>

<div class="option_properties">

  - *Type:* python3 packages in \`python3.withPackages\` format

  - *Default:* `"ps: []"`

  - *Example:*
    
    ``` nix
    (ps: with ps; [ python-language-server ])
    ```

</div>

</div>

<div class="option">

### `files`

<div class="option_description">

Files and folders to link into a folder in the runtimepath; outside of Envy
these would typically be locally-managed files in the `~/.config/nvim` folder.

</div>

<div class="option_properties">

  - *Type:* attribute set of (submodule)

  - *Default:* `{ }`

  - *Example:*
    
    ``` nix
    {
      autoload.source = ./neovim/autoload;
      ftplugin.source = ./neovim/ftplugin;
      "neosnippets/nix.snip".text = ''
        snippet nxo
        abbr    NixOS Module Option
        	mkOption {
        		type = with types; ''${1:str};
        		default = "''${2}";
        		description = ''
        		  ''${3}
        		'';
        		example = "''${4}''${0}";
        	};
      '';
    }
    ```

</div>

</div>

<div class="option">

### `files.<name>.enable`

<div class="option_description">

Whether or not this neovim file should be generated. This option allows specific
files to be disabled.

</div>

<div class="option_properties">

  - *Type:* boolean

  - *Default:* `true`

</div>

</div>

<div class="option">

### `files.<name>.source`

<div class="option_description">

Path to the file or directory to symlink in.

If the source is a directory, a directory with a corresponding name will be
created in the folder added to the neovim runtimepath, with symlinks to files in
the source directory, and same the treatment applied recursively for child
directories.

Overrides the text option if both are set.

</div>

<div class="option_properties">

  - *Type:* path

</div>

</div>

<div class="option">

### `files.<name>.target`

<div class="option_description">

Name of the symlink, relative to the folder added to the neovim runtimepath.
Defaults to the attribute name.

</div>

<div class="option_properties">

  - *Type:* string

</div>

</div>

<div class="option">

### `files.<name>.text`

<div class="option_description">

Literal text of the file. Used to generate a file to set the source option.

</div>

<div class="option_properties">

  - *Type:* null or strings concatenated with "\\n"

  - *Default:* `null`

</div>

</div>

<div class="option">

### `mergePlugins`

<div class="option_description">

Whether or not to collect plugins into "buckets" based upon their position in
the load order, and then merge those which can be merged, in order to minimise
the number of directories added to vim's `runtimepath`, decreasing startup time.

</div>

<div class="option_properties">

  - *Type:* boolean

  - *Default:* `false`

</div>

</div>

<div class="option">

### `neovimPackage`

<div class="option_description">

The base neovim package to wrap.

</div>

<div class="option_properties">

  - *Type:* package

  - *Default:* `"pkgs.neovim-unwrapped"`

</div>

</div>

<div class="option">

### `pluginRegistry`

<div class="option_description">

An attribute set describing the available/known neovim plugins.

</div>

<div class="option_properties">

  - *Type:* attribute set of (submodule)

  - *Default:* `{ }`

  - *Example:*
    
    ``` nix
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
        extraConfig = ''
          " Prettify NERDTree
          let NERDTreeMinimalUI = 1
          let NERDTreeDirArrows = 1
        '';
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
    ```

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.enable`

<div class="option_description">

Whether or not this neovim plugin should be installed and used.

</div>

<div class="option_properties">

  - *Type:* boolean

  - *Default:* `false`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.after`

<div class="option_description">

List of other vim plugins that this plugin should be loaded *after*.

This can be seen as a "soft" form of making each of the listed plugins
dependencies of this plugin.

Items can either be existing vim plugin derivations, or strings corresponding to
`pluginRegistry` attributes.

</div>

<div class="option_properties">

  - *Type:* list of string

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.before`

<div class="option_description">

List of other vim plugins that this plugin should be loaded *before*.

This can be seen as a "soft" form of making this plugin a dependency of each of
the listed plugins.

Items can either be existing vim plugin derivations, or strings corresponding to
`pluginRegistry` attributes.

</div>

<div class="option_properties">

  - *Type:* list of string

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.binDeps`

<div class="option_description">

A list of derivations containing executables that need to be available in the
`$PATH` of the neovim process for this plugin to use.

</div>

<div class="option_properties">

  - *Type:* list of package

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.condition`

<div class="option_description">

A VimL expression that will be evaluated to determine whether or not to execute
the vim-plug 'Plug' command for this plugin (which will typically load the
plugin, or configure it to be lazily loaded).

Leave null in order to unconditionally always run the 'Plug' command for this
plugin.

</div>

<div class="option_properties">

  - *Type:* null or string

  - *Default:* `null`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.dependencies`

<div class="option_description">

List of other vim plugins that are dependencies of this plugin.

Items can either be existing vim plugin derivations, or strings corresponding to
`pluginRegistry` attributes.

</div>

<div class="option_properties">

  - *Type:* list of (string or package)

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.dir`

<div class="option_description">

If set, specifies a directory path that the plugin should be loaded from at
neovim run-time, avoiding the use of a Nix-provided plugin directory.

Relative paths will be relative to the generated `init.vim`, which is in the Nix
store. As the value is passed into a '-quoted VimL string, it is possible to
escape this to use a relative path, e.g.:

``` nix
' . $HOME. '/.config/vim/local/some-plugin
```

If this is set, `source` will not be used.

</div>

<div class="option_properties">

  - *Type:* null or string

  - *Default:* `null`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.extraConfig`

<div class="option_description">

Extra lines of `init.vim` configuration associated with this plugin, that need
to be executed after the plugin loading.

Leave null if no such extra configuration is required.

</div>

<div class="option_properties">

  - *Type:* null or strings concatenated with "\\n"

  - *Default:* `null`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.for`

<div class="option_description">

One or more filetypes that should trigger on-demand/lazy loading of this plugin.

Can be specified with either a single string or list of strings.

NOTE: Lazy-loading functionality will likely conflict with the use of any
additional, non-Envy plugin manager.

</div>

<div class="option_properties">

  - *Type:* string or list of string

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.luaDeps`

<div class="option_description">

A function that takes an attribute set of Lua packages (typically passed from
nixpkgs) and returns a list of Lua packages that this plugin depends on.

</div>

<div class="option_properties">

  - *Type:* lua packages in \`lua.withPackages\` format

  - *Default:* `"packageSet: []"`

  - *Example:*
    
    ``` nix
    (packageSet: with packageSet: [ luafilesystem ])
    ```

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.mergeable`

<div class="option_description">

Whether or not it is safe to merge this plugin with others in the same bucket in
the load order.

</div>

<div class="option_properties">

  - *Type:* boolean

  - *Default:* `true`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.on_cmd`

<div class="option_description">

One or more commands that should trigger on-demand/lazy loading of this plugin.

Can be specified with either a single string or list of strings.

NOTE: Lazy-loading functionality will likely conflict with the use of any
additional, non-Envy plugin manager.

</div>

<div class="option_properties">

  - *Type:* string or list of string

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.on_map`

<div class="option_description">

One or more \<Plug\>-mappings that should trigger on-demand/lazy loading of this
plugin.

Can be specified with either a single string or list of strings.

NOTE: Lazy-loading functionality will likely conflict with the use of any
additional, non-Envy plugin manager.

</div>

<div class="option_properties">

  - *Type:* string or list of string

  - *Default:* `[ ]`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.remote.python3`

<div class="option_description">

Whether or not this plugin requires the remote plugin host for Python 3.

Will effectively be set to true if any Python 3 package dependencies are
specified for this plugin.

</div>

<div class="option_properties">

  - *Type:* boolean

  - *Default:* `false`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.remote.python3Deps`

<div class="option_description">

A function that takes an attribute set of Python 3 packages (typically passed
from nixpkgs) and returns a list of Python 3 packages that this plugin depends
on.

</div>

<div class="option_properties">

  - *Type:* python3 packages in \`python3.withPackages\` format

  - *Default:* `"packageSet: []"`

  - *Example:*
    
    ``` nix
    (packageSet: with packageSet: [ python-language-server ])
    ```

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.rtp`

<div class="option_description">

Subdirectory of the plugin source that contains the Vim plugin.

Leave as `null` to simply use the root of the source.

</div>

<div class="option_properties">

  - *Type:* null or string

  - *Default:* `null`

</div>

</div>

<div class="option">

### `pluginRegistry.<name>.source`

<div class="option_description">

Source of the vim plugin.

Set to an existing vim plugin derivation, or to a Nix store path to build a vim
plugin derivation from. Otherwise, leave this as `null` and set the `dir`
configuration option for this plugin instead.

</div>

<div class="option_properties">

  - *Type:* null or path or package or string

  - *Default:* `null`

</div>

</div>

<div class="option">

### `prePluginConfig`

<div class="option_description">

Extra lines of `init.vim` configuration to append to the generated ones,
immediately prior to any `pluginRegistry.<pluginName>.extraConfig` config lines.

Leave null if no such extra configuration is required.

</div>

<div class="option_properties">

  - *Type:* null or strings concatenated with "\\n"

  - *Default:* `null`

</div>

</div>

<div class="option">

### `withPython3`

<div class="option_description">

Enable Python 3 provider. Set to `true` to use Python 3 plugins.

</div>

<div class="option_properties">

  - *Type:* boolean

  - *Default:* `false`

</div>

</div>
