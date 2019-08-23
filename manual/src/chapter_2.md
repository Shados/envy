# 2. Module Configuration

The full set of available configuration options is documented in Appendix A;
this chapter serves as an overview of the configuration process and provides
examples of how the options may be used.

Broadly, the process for configuring Envy is:
1) Add non-plugin `init.vim` configuration.
2) Enable the plugins you want to use.
3) Specify any additional dependencies the plugins may have.
4) Add per-plugin configuration.
5) Pre-fetch and pin any shortname plugins (see chapter 3).



## Non-plugin Configuration
Adapt your non-plugin `init.vim` configuration to use Envy's module options.

By "non-plugin" here we mean specifically things that either don't depend
on/configure *any* plugin, *or* that could depend on any one of several plugins
(in which case, you should use Nix functionality to check which/whether any of
those plugins are enabled and adapt the generated configuration appropriately).

Envy provides a wide array of options here, so some examples may be helpful:
```nix
{{#include ../embedded/non-plugin.nix}}
```

## Enabling Plugins
You can enable both pre-existing Nix vim plugin derivations (e.g. from
nixpkgs), and vim plugins on github, both by using
`pluginRegistry.<pluginName>.enable`.

There are several ways to specify the source for a plugin, depending on what
you want:
```nix
{{#include ../embedded/enabling-plugins.nix}}
```

## Specifying Dependencies
Envy allows for specifying a wide variety of dependency types:
```nix
{{#include ../embedded/plugin-deps.nix}}
```

Inter-plugin dependencies also determine the order in which Vim plugins are
loaded at Vim run-time (by [vim-plug](https://github.com/junegunn/vim-plug)).

There are additionally two "soft" dependency options (`before` and `after`,
both of which take lists of plugin names only), that change how plugins are
ordered if both are enabled, but does not cause the "dependency" to be enabled
if the "dependent" plugin is, e.g.:
```nix
{{#include ../embedded/plugin-ordering.nix}}
```

## Plugin Configuration
There are per-plugin versions of the `earlyConfig`, `prePluginConfig`, and
`postPluginConfig` options under `pluginRegistry.<pluginName>.nvimrc`, named
`early`, `prePlugin`, and `postPlugin` respectively. These are inserted into
the generated neovim `init.vim` file immediately after or before the generic
versions.
